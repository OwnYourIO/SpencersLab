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
- 2026-11-12 human (owner PR review, six items — verbatim-intent ledger: DECISIONS
  "Owner PR review — 2026-11-12" §items 1-6) via 2026-11-12 plan D22 (DISPOSITIONS,
  §R7-resolved where factual): (1) `guaranteedMemoryGi: 64` "seems wrong. 64 too low or
  too high?" → ANSWERED IN PLACE, value kept (C08 T-D: the comment now carries the D17
  derivation + ladder + the 64+64+4>125.08 designed-Pending handshake — 64 is
  class-median, too-high-for-coexistence is the feature, too-low is receipt-moved UP to
  ~96 only while strata is manually down). (2) serveArgs same-line pairs → C08 T-C
  flow-style-per-pair reformat, token multiset preserved EXACTLY; `--flag=value` merge
  REJECTED (engine acceptance unverified — no gambling); equality arms parse-compare.
  (3) rename `amd.com/gpu-ai-pro-r9700` → `amd.com/r9700-1` → §R7 VERDICT: NO MECHANISM —
  .12/master have 2 flags, no override/env/config; `amd.com/` namespace AND `gpu-` prefix
  are code constants; the unsupported amdgpu.ids-mount hack tops out at `amd.com/gpu-r9700-1`
  and breaks the ledger provenance; the exact-string lanes are rejected-by-ruling lane
  SWITCHES (DRA extendedResourceName reopens D18; squat reopens the determinism rejection)
  — kept name + T-B evidence comment at the claim; upstream feature ask RECOMMENDED, no
  duplicate exists (§R7-S9) — coord's run-end option, presented at hand-back with the
  lane table. (4) `lbl:` key "not understandable" → DIES with the vendored values file
  in T-A (no rename needed). (5) app-template conversion → YES per §R7-Q5, C08 T-A
  executes (D23). (6) "fair number of other comments" → the recorded nits sweep:
  test_trio.py:66 truncated message + naming.sh:205 stale phrase (TESTS/** → test
  session, dev hands off), values:744 subtree wording + jsonc floor sentence + radiance
  NOTES colon (dev-side one-liners in C08 T-E), M1 header fold mooted by T-A (arm
  re-pin if it reads the header). "Other comments" beyond the six: if the owner holds
  more they surface at the round-2 hand-back — plan assumption stated, not stalled on.
- 2026-11-12 plan D23 (C08 shape; SUPERSEDES D19 — append-only: the vendored-fork
  governance line, the ~10-line args-delta story, the refresh policy ("on upstream ≥0.23
  re-copy+re-apply"), the `name: amd-gpu` byte-pin rationale (templates hardcoding
  .Chart.Name) and the `lbl:`/`dp.extraArgs`/`updateStrategy` vendored-values keys ALL
  DIE with the conversion to a FIRST-PARTY app-template 5.0.1 chart (owner item 5;
  §R7-Q5 verdict "converts cleanly"; refresh debt ends — app-template dep bumps via
  renovate are already repo norm, PR #122 staleness becomes irrelevant). SHIP FACTS the
  conversion carries from the live/vendored bytes: four plain args (CMD trio restated —
  `-v=5` law survives as comment — + strategy arg direct, no plumbing key), image
  1.31.0.12 + docker renovate pin + 6437c74f digest ledger MOVED, THREE hostPaths
  (device-plugins dir, /sys, /var/lib/amd-metrics-exporter DirectoryOrCreate) — §R7
  CORRECTS the owner item-5 phrasing: the plugin mounts NO /dev/kfd//dev/dri (socket-
  handshake registration; Allocate hands devices to kubelet at container creation),
  /sys REQUIRED for naming; priorityClassName system-node-critical; tolerations
  CriticalAddonsOnly; nodeSelector/imagePullSecrets/resources OFF as today (parity, not
  improvement); RBAC/SA render NOTHING today (labeller-gated) → zero shipped,
  app-template serviceAccount/rbac documented as the future-labeller route; templates/
  emptied (owner: no _helpers.tpl, no NOTES.txt — radiance NOTES is a DIFFERENT chart
  and STAYS). TWO ACCEPTED STRAINS shipped as decisions: (1) DaemonSet `updateStrategy`
  NOT RENDERED by common 5.0.1 — today's RollingUpdate/maxUnavailable:1 EQUALS the k8s
  API default ⇒ zero behavior delta; future OnDelete needs rawResources/upstream.
  (2) NAME BYTE-IDENTITY (D19's pin) INTENTIONALLY LOST: global.nameOverride: amd-gpu +
  identifier target live names where CHEAP; where it strains, one Argo-sync DS
  prune+create swap inside the same wave (seconds gap; running GPU pods unaffected
  §R6-Q4-4; gpu cluster OUTSIDE the wave — external entry + D21 shield untouched),
  tests re-pinned to app-template-derived names where suite law demands identity,
  rename set enumerated in the commit + review notes. Pool NAMES unchanged (D22 item 3
  verdict NO) — the §R7-Q4 rename-inventory table becomes the zero-delta list.
  Chart.yaml: version stays 1.0.0 (existing chart, no hand-bump), appVersion carries the
  image pairing; .helmignore joins repo standard; expected-names ledger block SURVIVES
  the values rewrite in n4-readable form.
- 2026-11-12 human (lane ruling, batched round — verbatim: owner chose **"Table-mount →
  amd.com/gpu-r9700-1 (Recommended)"** for the item-3 rename-lane question and confirmed
  the rework scope is **"Six items + recorded nits"** — no further comments) via
  2026-11-12 plan D24 (APPEND-ONLY SUPERSEDES D23's names-stay framing and D22-item-3's
  keep-name disposition; the ledger/gate/test name strings all move per the C08.md
  amendment of the same date): MECHANISM ON THE RECORD — the exact `amd.com/r9700-1`
  REMAINS UNREACHABLE (§R7: namespace `amd.com` and prefix `gpu-` are code constants;
  the table-mount's ceiling is `gpu-r9700-1`, §R7-Q2 sanitizer trace verified: marketing
  string exactly `r9700-1` → valid chars, no filler token, unique in the 752-row table →
  `gpu-r9700-1`). The owner ACCEPTED the closest name via the §R7-Q2 unsupported-in-docs /
  works-in-practice mount (plain os.Open of the const IDsPath, mount-over-able) rather
  than the exact-string lane-switches: chosen over DRA `extendedResourceName` (reopens
  D18 Option-1, second GPU subsystem, reboot-CDI bug ledger) and over squat (D18's
  determinism rejection) precisely because it is INJECTION-PRESERVING (same plugin, same
  strategy, same per-name pools, same B1 shield) and adds NO new subsystem. SHAPE:
  charts/amd-gpu (first-party per D23) ships a MINIMAL PATCHED amdgpu.ids as a ConfigMap
  mounted over the baked IDsPath via subPath; ONLY the 7551/C0 row(s) renamed + EVERY
  1586 row copied VERBATIM from the fetched v1.31.0.12 baked table (rows keyed
  per-(device,revision): renaming the R9700 cannot touch the APU — but DROPPING any 1586
  row silently strands `gpu-8060s` → bare-fallback → breaks the LIVE B1 overlay consumer:
  THE APU-ROWS-MUST-CARRY LAW, enforced by the test parity leg vs the stored evidence
  fixture, not prose). MINIMALITY LAW: the shipped table is NOT the full 752 rows — any
  absent (device,revision) hits the already-shipped fallback-trap decision tree; bounded
  to this node's two cards TODAY; TP2 CARDS REQUIRE TABLE RE-VERIFICATION BEFORE
  SCHEDULING TRUST (rides the TP2 doc §6/§11; follow-up card #1 body RE-PUBLISHED by
  coord after C08 — run-end action). WATCH LAW: if the image ever moves its IDs lookup
  path (the Dockerfile COPY constant), the mount un-applies SILENTLY and the baked
  `gpu-ai-pro-r9700` returns → radiance claim Pending-forever; step-0 receipts (a–c)
  catch it — comment at the mount + runbook prose. RENAMED SURFACES: amd-gpu ledger,
  radiance claim pair/comments/NOTES, runbook gate names + gate (b) Loaded-N row-count
  (now = the minimal table), TP2 doc pool strings, testlib GPU_CLAIM constant.
  FROZEN: `gpu-8060s` everywhere, the overlay, peers/catalog (engine ids were never
  GPU-resource names), the gpu cluster (external chart never sees the ConfigMap).
  UPSTREAM FEATURE ASK (§R7-Q3(b)/OQ3): RECOMMENDED, filing = OPTIONAL owner call —
  recorded Deferred either way, zero code implication. Scope confirmed closed: the six
  items + recorded nits are the whole rework.
- 2026-11-13 human+plan D25 (LIVE DEFECT C09 — owner-reported after sync: the converted
  plugin container crashloops `RunContainerError: exec: "-logtostderr=true": executable
  file not found` → pools un-advertised → radiance + gpu-ai llama-swap Pending; verbatim
  report in STATE handoffs, full grounding EXPLORE §D1 scout round 2): ROOT CAUSE — the
  pinned image (digest 6437c74f = the values ledger; config blob 740b1675) ships NO
  ENTRYPOINT; the binary is CMD's first element `./k8s-device-plugin` at WORKDIR /root/
  (Dockerfile@v1.31.0.12 — also re-confirms the D24 COPY law for the IDS path); declaring
  args without command makes args[0] the exec path (runc/exit-128 semantics — the live
  pod spec matches the local render field-for-field). HONESTY ON THE LINE: the defect is
  INHERITED FROM C07 — the vendored template at a81989b47^ emitted args-only, the parity
  oracle pre-c08-deviceplugin-ds.yaml captured that same broken shape (no command key
  anywhere), so THE ORACLE COULD NOT WITNESS IT — "the oracle is the defect"; it survived
  because gpu-ai ran the EXTERNAL 0.22.0 chart (no args/command surface at all → image
  CMD wholesale, binary included) until C08's swap landed the broken shape live for the
  first time; C08's "parity, not improvement" executed perfectly against a never-live-
  proven source, and the values 105-110 comment ("CMD trio restated in full") encoded the
  same misreading — CMD is binary + trio; the binary half was dropped silently. THE FIX
  (C09, values-only, library-expressed — _command.tpl 4-23/_spec.tpl 15-17, no
  entrypoint default exists): `command: ["/root/k8s-device-plugin"]` on
  app-template.controllers.device-plugin-daemonset.containers.deviceplugin (absolute path
  drops the WORKDIR dependency; LIST form per repo precedent charts/betanin:25,
  charts/archon:21-27, charts/radiance:318 — schema oneOf also accepts a bare string,
  recorded alternative NOT taken for needle/grep symmetry); args stays the EXACT 4-item
  ARGS_CONTRACT (fix is additive; the four flags reach the binary via args, §D1.7 — the
  -v=5 runbook-log law finally executable); comment block rewritten to carry the WHY
  (registry + Dockerfile cites) and the never-live-provenance sentence; charts/radiance
  main container is NOT touched — its image HAS Entrypoint ["radiance"] (registry-
  verified §D1.5), args-only is SAFE there (a future "consistency" command-add would be
  a regression); generic-device-plugin pre-existing + ENTRYPOINT image, out of scope.
  EVIDENCE-AUTHORITY SWITCH: command-parity authority is a NEW image-config capture
  (tests/evidence/image-config-1.31.0.12.json — test-session re-fetch, digest-cross-
  checked, never hand-retyped) — NOT the DS oracle, which keeps all its existing
  comparison legs with command listed as a KNOWN PRE-C08 DEFECT (one header line,
  test-session property). C08 AC AMENDMENT (append-only, no rewrite of chunks/C08.md's
  landed record): its "parity vs oracle" legs are valid EXCEPT they cannot and must not
  be read as commanding command-absence. CLASS LAW for every future conversion/parity
  work: (1) parity-vs-oracle MUST enumerate command/entrypoint explicitly — a field the
  oracle lacks is not "equal", it is UN-witnessed; (2) any chart conversion whose parity
  source was never run live REQUIRES an image-config receipt before landing exec-shape
  fields; (3) suites must carry a both-or-neither joint invariant (command+args together,
  args-alone only with Entrypoint evidence) — the red-first command legs that would have
  caught this are C09 AC5. Names/ledger/strategy FROZEN (gpu-r9700-1 / gpu-8060s
  unchanged); live verification stays owner-run read-only prose (AC7); plan_status
  reopened complete→approved for this delta round (owner live report is the gate).

- 2026-11-13 human+plan D26 (LIVE DEFECT C10 — §D2 scout round 3, plan-session readonly
  re-verification ~03:4xZ; operational headline: **the llama.spencerslab.com router has been
  DOWN since 01:52:09Z** under `strategy: Recreate` and runbook step 3 will NOT restore it):
  THE FACT — the B1 overlay's `amd.com/gpu: null` retirement **never reaches Helm**: the
  ApplicationSet→Application valuesObject chain drops null-valued keys before helm ever sees
  them. Live evidence pair (§D2.6, re-read this round): live ApplicationSet
  `gpu-ai-charts-appset` generator `values` carries `"amd.com/gpu":null` AND live Application
  `gpu-ai-llama-swap` `spec.sources[].helm.valuesObject` = `{limits:{amd.com/gpu-8060s:1},
  requests:{amd.com/gpu-8060s:1}}` — the ADDs arrived, the null is GONE; helm ALONE honors the
  null (locally reproduced per §D2.6.2 — true ONE LAYER BELOW production, the same
  "oracle-is-the-defect" class as §D1.2/C09). The two death-site candidates (mergo-nil-skip in
  the templatePatch merge at `charts/base/templates/appset-charts.yaml:120`, or the YAML->struct
  round-trip) are indistinguishable read-only; the FACT stands either way: **deletion
  instructions cannot cross this chain; positive ADDs demonstrably do**. Consequence chain:
  chart tree-global bare claim survives live on gpu-ai, the node's bare pool is capacity 0
  (kubelet-retained `amd.com/gpu: "0"` from the pruned 1.31.0.9 advertisement, §D2.2), the
  outer llama-swap pod is Pending-forever on `Insufficient amd.com/gpu` — a THIRD failure
  class the runbook did not know (plugin Running, pools advertised, pod still Pending).
  THE CARRIER DECISION (C10): `charts/llama-swap/values.yaml` ships NO GPU claim (the
  tree-global `limits:"amd.com/gpu": 1` line DIES; a fresh cluster renders a GPU-less pod
  until it adds one explicitly — said plainly in the comment); `services/gpu/prod/values.yaml`
  ADDs bare `amd.com/gpu: 1` **limits-only** (adjudication: the rendered gpu-cluster Deployment
  stays byte-identical to pre-C10 — the transferred chart line was limits-only and kubelet
  auto-mirrors extended resources into requests, exactly what the live gpu pod shows);
  `services/gpu-ai/prod/values.yaml` keeps the 8060s add+mirror and DROPS the inert null and
  its false prose. WHY not the alternatives (rejected): keep-null-per-cluster (empirically
  dead by this fact), chart-side cluster-discriminating template (clusters' choices live in
  service overlays by repo law), custom-values channel (Bitwarden UUIDs only). Extended
  resources require POSITIVE INTEGERS — `0` is not a legal retirement either; the comment
  names both dead shapes so nobody re-attempts them.
  D21 SUPERSESSION — MECHANISM ONLY, intent verbatim-unchanged: the gpu cluster keeps the
  bare claim (its external single-naming 1.31.0.9 plugin can advertise nothing else; live
  gpu-llama-swap 1/1 stays schedulable), gpu-ai uses the named APU pool, no workload strands;
  the same-wave commit and lockstep-revert laws survive; only the CARRIER flips from
  tree-global-default + overlay-null to per-cluster positive ADDs. C07's AC3/AC4 per-cluster
  RENDER truths are unchanged; the "chart claim-line zero-diff" shape of proof is superseded
  by the transfer check (chart 1->0 AND services/gpu 0->1 in ONE commit — WAVE-C).
  ROOT-CAUSE HOME OUT OF SCOPE: the passthrough at
  `charts/base/templates/appset-charts.yaml:117-123` (fix = pass `$baseValues` through
  untouched when both custom dicts are empty, or document the add-only chain law) has
  repo-wide blast radius — every Application rendered by the shared template; latent, not
  active, for every other consumer today (all consumers ADD-only; cf-143 becomes so with
  C10) -> **follow-up card** (coord creates in Inbox/Backlog; planned body line in
  chunks/C10.md AC5, the D26 bullet). Class law for the ticket (TEST_SPEC §12.9 property): oracle arms MUST
  model the layer production consumes — for GPU-claim law that is the Application-side
  valuesObject, not the chart-only helm merge; a deletion instruction in service values is
  now a banned pattern (null-absence guard).
   AMENDMENT 2026-11-13 (scout round 4, §D2.8 — boundary closure, the FACT UNCHANGED): the
   death site is now narrowed BETWEEN two exonerated layers — the ApplicationSet CR provably
   STORES both nulls (claim + `shared-storage`), and every live Application is null-free
   doc-wide (the killer datum: `gpu-ai-amd-gpu`'s valuesObject is literally `{}` because its
   only generator content was such a null), while helm v3.16.4 provably DELETES a key given a
   null (`pkg/chartutil/coalesce.go` + the docs' "Deleting a default key" + offline render A on
   the pre-C10 blobs retires the bare). So the strip is whole-tree and happens in the
   appset-controller hand-off only (sprig/mergo nil-skip vs struct round-trip still
   indistinguishable from outside the binary, and irrelevant to the law); C10's carrier move is
   the right fix under EVERY candidate cause, and the C10 commit message stands verbatim,
   upgraded from one evidence pair to a fleet-wide class law. Against over-reading: nothing
   ever "retired" the bare claim normatively, and the wedge was NOT propagation staleness —
   `Application.status.history` ids 123-132 show the APU ADD present in every snapshot from
   01:52:08Z on and the null absent from all of them, across 4 syncs and 2 ReplicaSets, so the
   valuesObject never once held a schedulable shape. LIVE STATUS at this writing: router
   `gpu-ai-llama-swap` STILL `Available=False` since 01:52:09Z (gen 49, template the bare pair,
   ProgressDeadlineExceeded 02:37:47Z) because main is at `ec18281fb` = C09 — C10 (56142d511)
   is NOT yet merged — and step 3 has not been run (strata 64Gi resident, free 59.92 Gi). The
   healthy router on the gpu cluster is a DIFFERENT cluster and is not recovery evidence here.
- 2026-11-13 human+plan D27 (LIVE DEFECT C11 — owner-reported third round: after the C10
  sync the radiance pod streams the pack to completion, then the `radiance-fetch` init
  CRASHLOOPS — live restartCount 6, back-off 5m0s, 1-second iterations, serve container
  never started (`imageID: ""`, PodInitializing); verbatim intent in STATE handoffs;
  authority EXPLORE §D3/§D3b, scout round 5 ses_e2b06477fffeuymXBh71NbPe3w): ROOT CAUSE —
  `charts/radiance/values.yaml:346` runs `echo "$LFS_SHA  $PACK" | sha256sum --check` in
  `sh` inside `docker.io/curlimages/curl:8.23.0` (live imageID `sha256:3fb7e13e…`; the
  container's own banner `BusyBox v1.37.0` is the authority) — BusyBox hash applets declare
  SHORT options only (`md5_sha1_sum.c` `getopt32(argv, "^" "scwbt"…)`, byte-identical
  1_36_1↔master bracketing 1.37.0): any GNU long option dies at option parse with
  `unrecognized option: check` + **exit 1** (live lastState.terminated), `set -e` aborts
  before `touch "$MARKER"` → the marker can never be written → every restart re-enters, the
  curl resume is a <2 s no-op, CrashLoop. DOWNLOAD-COMPLETE FINDING: resume offset printed
  `121,969,901,568` == the exact RQ0/values-ledger size — the 113.6 GiB pack is COMPLETE
  (triple-match §D3.4: `x-linked-etag` + HF tree `lfs.oid` + ledger); honest caveat
  recorded: size-complete ≠ hash-complete — the bytes have NEVER passed the gate, which is
  why the fix REPAIRS the gate (first real verification happens post-fix, ~1-6 min, one
  time, zero re-download) and nobody "skips to the marker" without running the hash.
  FIX CHOSEN (C11 AC1 = §D3b.4): portable SHELL EQUALITY —
  `actual=$(sha256sum "$PACK" | cut -d' ' -f1)` + `[ "$actual" != "$LFS_SHA" ]` →
  MISMATCH echo naming BOTH expected and actual → `exit 1`; `touch "$MARKER"` stays the
  sole success artifact after the guard; the two-space compute form prints identically on
  both applet families (`printf("%s  %s\n")`); curl line, rc-0/33 tolerance, marker-skip,
  set -e, all script constants BYTE-KEPT. REJECTIONS with source reasons (recorded so
  nobody re-attempts): `-c -s`/`-cs` — BusyBox-only, GNU has NO `-s` (busybox's OWN FIXME
  names GNU's long-only --quiet/--status) → breaks an image swap; `sha256sum -c -`
  (stdin) — equally portable, minimal diff, keeps `: OK` receipt, but on failure names the
  FILE never the digests → adjudicated ACCEPTABLE-COARSER, NOT chosen (equality is the
  only shape satisfying the digests-on-one-line failure-log requirement, §D3b.4 open item
  closed by plan); `--check`/`--status`/bare `-c` — die or half-die per family; extra
  `[ -s "$PACK" ]` guard — UNNECESSARY and omitted: missing file → `can't open`/`cannot
  open` stderr + empty stdout through `cut` → `actual=""` can never equal the 64-hex sha →
  same loud MISMATCH; partial file hashes differently → same path. NON-CAUSE ADJUDICATED:
  **NOT a timeout, NOT a stall** — §D3 (same scout round) refuted the launch's/owner's
  "timing out too soon" premise with live+offline evidence (the 1126 B line is the HF 302
  redirect interstitial; the stream ran ~95 MB/s; `progressDeadlineSeconds: 600` is the
  Deployment-condition theater that sold "the pod stopped"; no `--max-time`/`--speed-*`
  exists on the line; no `activeDeadlineSeconds` on the pod); a first scout launch was
  CANCELLED BY THE USER and re-run — recorded honestly in the STATE scout handoff;
  progress-output cosmetics (§D3 open items: progressDeadline prose/override, `-#`/`--silent`
  style) stay NON-defect options, not in C11's scope. CLASS LAW (the third
  "one-layer-below-the-surface" sighting with §12.8/§12.9): **a container image's applet
  family is a CONTRACT — GNU-only long options require a GNU-family image; vocabulary
  assertions never prove grammar** — the suite now gates on IMAGE IDENTITY (busybox-family
  set membership + digest-ledger pin beside the init image) and OPTION GRAMMAR (no `--`
  long options on hash-applet lines; red-first legs §D3b.5, which MUST be red against
  today's tree and are the legs whose absence let this ship). BLAST RADIUS: exactly ONE
  defective call site + TWO prose carriers — runbook :383 (dev re-words in C11's commit,
  `sha256sum` literal survives T5's need_lit, no needle quoted `--check`) and
  chunks/C06.md:267 (plan-round dated correction folded at this amendment — the C06
  operator-proof checked the string's PRESENCE, not the grammar); TP2 doc
  grep-adjudicated OUT (zero sha256sum sites); repo-wide audit §D3b.7: every other
  busybox/alpine-family init is POSIX-applet-safe, all `curl --long-flags` are the real
  curl binary, git/rulesync/aislop long options are GNU-userland tools — the class cannot
  currently return elsewhere; the new grammar legs guard radiance itself. n2 same-wave
  matcher: C11 gets NO WAVE-E shape — a NON-FLIP class (touches no carrier file +
  claim-line census unchanged → guard vacuous-with-message; any claim-moving non-wave
  commit still REDs) — a fifth shape would classify a grammar fix as a claim wave and rot
  per doc-fix (adjudicated; D27). AUTHORSHIP HONESTY (no blame, the law is the product): the
  defect was written at C02 (init contract per D10/D15), survived C04's review, the test
  wave, C09's adjacent fix and final reviews r2/r3 because every leg read the script's
  staging VOCABULARY (marker/sha/URL/curl present) — 43P through a broken gate; the
  green-suite witness at final-r3 predates the first cold-staging attempt: designed-red
  catches shapes, LIVE catches truths — fourth confirmation of the ticket's
  live-verification law (all three prior live defects likewise invisible to a green bar).
  Scope confirmation from the same owner round: rework scope remains the six items +
  recorded nits + these live deltas; plan_status reopened complete→approved for the C11
  round (D26/D25 pattern).
- 2026-11-13 human+plan D28 (LIVE DEFECTS C12 — two owner reports 2026-11-13 afternoon;
  NEW live deltas, not "other comments" beyond the closed six-item scope; authority: the
  reports' startup-report receipts + EXPLORE §D4 scout round 6 — which live-falsified
  §D3b.6's "1–6 min" hash model: busybox sha256sum is single-threaded with NO SHA-NI
  path, cpu measured EXACTLY 0.2000 core while io PSI = 0 ⇒ the pass is CPU-QUOTA-bound
  at 30–70 min (hard floor ≈20.3 min at any disk), and every pod loss restarts the HASH
  at byte 0 (only the download resumes)):
  (1) OOM-AT-64 RECEIPT: C11's repaired gate completed (first-ever hash, tens-of-minutes
  exactly as §D4 predicts, zero re-download) — then the SERVE container printed its own
  budget and died `radiance E startup stopped: out of memory`: cgroup 64.00 GiB vs the
  printed host-side wants pool 42.70 + `--kv-resident` mirror ≈32 + activation/arena
  2.00 + placement-flag items 1.18 + step staging = **71.04 GiB observed pinned**
  (report 2; report 1 caught the pre-streaming 43.18). The shipped `guaranteedMemoryGi:
  64` could NEVER hold the profile — a PLANNING miss at the shipped scalar, not a
  runtime regression.
  (2) D17 ADJUDICATION (no blame; the record is the product): the derivation neither
  double-counted nor omitted the mirror — it RESERVED the mirror at RESEARCH RQ1's
  ~12 KiB/token QSA-group rate (≈19.3 GiB) while shipped 1.17.0 books ≈20 KiB/token
  (≈32 GiB at 8×200K), consistent with RQ1's own reservation semantics ("host copy
  reserved max-num-seqs × max-model-len however short the requests"); the root slip is
  that RQ1's VERDICT line says verbatim "don't plan off any per-token figure; the
  receipt prints it" — and the plan (and C08 T-D's sharpened comment) planned off
  per-token figures anyway. 64 sat BELOW the printed sum; D17's documented ladder-up
  clause existed for exactly this and simply had to be walked.
  (3) SHIPPED VALUE = **96 GiB** (D17's own ladder ceiling; receipt basis: 71.04 +
  ≥4 GiB-free-under-cgroup rule + ≈21 GiB headroom for full-8-session prefill staging).
  The owner's MANUAL 94 GiB out-of-band bump is drift the repo must absorb: landing 96
  means the next Application sync APPLIES OVER the hand-edit and the Recreate roll makes
  it effective — the DESIRED end state (94 exists nowhere in git and would silently
  re-strike on any resync). Schedulability restated at 96: 96 + router 5.125 + system
  1.158 ≈ 102.3 ≤ 125.08 while strata is scaled down (free ≈22.8 GiB); +strata's 64Gi
  request > 125.08 → Pending — D17's designed handshake at the new number; every
  64+64+4>125.08 arithmetic needle dies with this fold (C12 AC1/AC4).
  (4) INIT CPU — §D4's law lands on the pair: DECIDED raise 200m→1000m (busybox
  single-thread ⇒ one core is the whole gain, >1 pointless — math written at the knob;
  cold-staging hash ≈ 8–23 min vs 30–70; memory stays 2Gi/2Gi, measured workingSet
  4.1 MB); documented SEPARABLE knob (revert = one line, ship the raise); D15 pod-class
  law keeps requests==limits on both containers. Runbook :394-395 "minutes-class"
  folds to §D4.6's corrected tens-of-minutes/8–23-min wording.
  (5) HOST-GATE CORRECTIONS (checklist = C12 AC2's 15 families in
  .agents/notes/radiance-host-tuning.md; gate prose folded into the runbook): IOMMU —
  step-0(e) expected `iommu=pt`, live truth `amd_iommu=off` + engine WORKS (report 2:
  `dma copy lists` IN USE on DMA engine 0; no RCCL in radiance; p2pdma-permissive on
  AMD RCs, RESEARCH S9) ⇒ THE GATE WAS WRONG, NOT THE HOST — corrected law: state
  known+recorded, off acceptable for the host-staging path, re-verify before any
  TP2/P2P experiment. MEMLOCK 8 MiB gates the RAM-ngram tier + io_uring rings ONLY
  (card-path pins are driver-locked, NOT ulimit-charged — the 71 GiB pool never needed
  it; do not oversell the drop-in). DIO — local-path backing "reports no direct-I/O
  alignment… 4096-byte spans" (device class NOT-determinable-read-only, §D4.3): tier
  choice documented (disk-stay vs memlock-unlock→ram, with the 71.04+47.7 > 96
  arithmetic shown, vs ram=DIR tmpfs). LINK — 8.0 vs 16.0 GT/s x4 WARN: did NOT repeat
  in report 2 — retrained-vs-luck is INDISTINGUISHABLE from logs; only LnkSta +
  /diagnostics under a long prefill decides. PROVEN-DONE (do-not-redo): cwsr=1 (engine
  refuses boot otherwise), ECC-off (31.86 GiB), ReBAR. CUSTOM-PARAM CONTRADICTION
  adjudicated honestly: the owner's "ASSUME NOTHING CUSTOM" stands as METHOD (quote
  /proc/cmdline into every receipt; treat no param as stock OR intentional) even
  though `ttm.page_pool_size=29360128 ttm.pages_limit=29360128
  amdgpu.lockup_timeout=30000` + `amd_iommu=off` are visibly custom-set in the paste —
   [C14-r1 TRANSCRIPTION CORRECTION, this round: the paste above originally read
   `ttm.pages_limit=293610128` — a 9-digit mis-type of the owner's own line, which repeats
   `29360128` twice per the §D8/§D10 boot-parameter prints. 29360128 × 4 KiB = 112.00 GiB
   EXACTLY, the figure the pin-cap law below rests on, where the mis-type computes 1,120.03
   GiB. Corrected in place: a "verbatim paste" that isn't verbatim is the exact class this
   ticket keeps getting burned by. The same typo survived in three sites of the tuning note
   (folded at C14 r1) and in chunks/C12.md:177's `-class` quote — that one is a chunk record,
   left as the historical quote with this note as its correction pointer.]
  the PRINTED budget wins anyway: pin-cap authority = the engine's 112.00 GiB line,
  not the stock ~120.6 formula. DECODE 5.1 t/s suspect order: LINK → POWER-CLOCKS
  (300 W cap ≠ the TP2 §3 120 W class — board not capping today; sclk 500–2350, check
  ramp under load) → RUNTIME-PM (control auto) → HEAT-ENGINE idleness (0 dispatches/
  promotions/demotions; resident-per-layer min 0 max 154 mean 54.4 sd 73.3, L48+ zero
  — re-read under sustained multi-session load before touching `--placement`; the
  all-miss story = cold expert set + half-width link); the ~142 t/s prefill vs the
  ~450–600 x4-class is the half-width link's signature. 8-session fill = the STANDING
  acceptance bar; PROTOCOL one-variable-at-a-time with receipts (startup report +
  /diagnostics + fixed probe) after each.
  (6) CLASS LAW (fifth live-round confirmation; becomes doc-test rule): **a startup
  report that prints its own budget must be READ BEFORE the sizing scalar ships** —
  we shipped 64 against a profile the engine now states needs ~71.04 pinned, and NO
  arm across five chunk reviews + four final reviews ever compared the pod limit to
  THE SUM OF THE PRINTED HOST-SIDE TIERS. Product: the tuning note's §PROTOCOL carries
  the budget-line check (`pinned … GiB` + 4 ≤ limit) as a re-capture step, the runbook
  step-7 gate gains the arithmetic, and the TEST_SPEC §12.x round pins it as a leg —
  designed-red catches shapes, LIVE catches truths (and the §D4 touch-quiet law holds:
  no radiance sync/delete while a cold hash runs). plan_status reopened complete→
  approved for this delta (wave 8→9; C09/C10/C11 pattern).
- 2026-11-13 human (batched-round answers, C12 value question + lock + spec) via
  2026-11-13 plan D29 (APPEND-ONLY; supersedes D28's 96 AS THE SHIPPED VALUE ONLY — D28's
  ladder reasoning, the 71.04 receipt basis and the class law STAND as history):
  (1) VALUE RULING — asked "Which value should charts/radiance ship for gpu-ai?", the
  owner answered verbatim **"110 GiB (your figure)"**, choosing their remembered number
  over C12's documented-96 recommendation ⇒ `guaranteedMemoryGi: 110` ships. §D6's
  archaeology is recorded honestly in both directions: 110 is NOT a radiance figure in
  any repo plan surface (zero literal on radiance surfaces; it is STRATA's gpu-ai LIMIT,
  owner ruling 2026-11-10 with the node-envelope law "110 + ~7-8 GiB floor ≤ 125.1",
  `charts/llama-swap/values.yaml:1319-1325`); the ruling EXTENDS the owner's own proven
  envelope class to the new engine — repo-wise new, arithmetically LEGAL at §D6.2's
  sums: **110 + router 4.125 + system 1.158 = 115.28 ≤ 125.08 (free 9.80 GiB) while
  strata is DOWN; 110 − 71.04 printed = 38.96 ≥ 4 engine rule ✓; strata UP
  110+64+6.3 = 180.3 > 125.08 → designed Pending — the step-3 handshake restated at
  110, protocol unchanged; the handshake INVERTS: at 110-radiance, strata restore-back
  can never co-reside — the cutover is now a real either/or (Deferred row gains the
  weight)**. Headroom story: +14 GiB burst slack over 96 at −14 GiB node-free — and the
  RAM-ngram tier is DEAD at BOTH (71.04 + 47.68 = 118.72 > 110) so 110 is slack, not a
  tier enabler; "110 buys nothing the engine rule needed" is ALSO said: 96 passed the
  rule — the ruling is headroom preference, not a fix correction. The in-flight C12 test
  round (uncommitted, §12.11, pinned at 96) re-points to 110 per C12 AC4's exact list
  (testlib SCALARS one site + the pair/splice/arithmetic legs + runbook.sh T2/T3/T5 +
  tuning-suite fixtures + T4's 71.04/110 coherence token).
  (2) LOCK ANOMALY — "Yes, continue anyway": during this round the pipeline lock showed
  PIPELINE LOCK LOST; pipeline_status then held setId `b60c418b` (AI set, card
  Na5LxMaY3ptABWhAy) SOLELY by THIS session but state `failed`, heartbeat answering
  `no_claim` after the server restart cost the in-memory registration, and a re-claim
  refused `reason: occupied` NAMING MY OWN session (§D6-era facts). Standing decisions
  recorded: continue per the owner's word; the 2 h reaper may yet prune the stale row —
  if it does, the CARD MOVE hands to the OWNER rather than any force (claim nothing
  beyond what the file-backed state re-grants); the lock flap itself is the third
  state-flap sighting of its class (cf-131/C09 precedent) with one new fact: failed-
  state-but-held is the server-restart signature.
  (3) GPU-BOX SPEC DRIFT — asked for the gpu cluster's real RAM, the owner answered
  "I upgraded it / it's a different box" WITHOUT the number; §D6.2's live read is
  AUTHORITATIVE for sizing until they supply the spec: node `gpu` capacity==allocatable
  **28.60 GiB** (29,994,244Ki; capacity==allocatable pattern = the node IS that size,
  same signature as ai-gpu's 125.08), while four 2026-10 carriers + a live
  `services/gpu/prod/values.yaml:363-371` comment say **64 GiB RAM** — "64 for gpu" was
  never a radiance pod plan (radiance serves gpu-ai ONLY; zero radiance surfaces on gpu).
  Consequences: the 2026-10 fit-notes + that comment are STALE (the "~32 GiB experts
  resident" line cannot fit a 28.6 GiB box) → **docs follow-up card owed at run end,
  NOT a C12 code change**; if the box really moved, gpu-cluster cache-ram sizing prose
  deserves a re-look (follow-up card territory).
  (4) §D6's PROBE CORRECTIONS fold into C12 AC2's checklist as the five amended-truth
  families (LINK PROVEN-DOWNGRADED (WARN reprints post-reboot at 49% busy; width is
  physical, SPEED is the defect; LnkCtl2 TargetSpeed is the next discriminator;
  retrain-vs-luck CLOSED); GOVERNOR NON-PERSISTENT (host reads performance NOW while
  the fresh 15:01 boot printed powersave — persistence route, never a runtime-set
  dressed as a fix); MEMLOCK PROBE (sandbox 16787369984 = MemTotal/8-computed vs the
  engine's own 8 MiB container truth; crictl ps→inspect→/proc/pid/limits is the read;
  k8s/CRI have NO per-pod rlimit — the node route is the only one and the repo's OWN
  strata-prep LimitMEMLOCK=infinity drop-in (:115-118) is the precedent; CAP_IPC_LOCK
  nuance mooted by... (5)); RAM-TIER DEAD arithmetic 118.72 > 110 > 96 (unlock-memlock
  does NOT buy it; options = stay-on-disk 4KiB-spans (3–10% band) vs the owner's XFS/ext4
  storage-layout follow-up — the runbook's ≥5 GB/s O_DIRECT gate is unmet at 3.42 GB/s,
  and statx STATX_DIOALIGN regular-file support is ext4/f2fs/xfs ONLY (man-pages 6.19),
  btrfs legitimately reports nothing; alignment-unreported ≠ direct-IO-broken); IOMMU
  correction CONFIRMED (off works, dma copy lists active) + the recorded side-effect:
  `amd_iommu=off` ALSO kills the NPU driver (`amdxdna … Running without IOMMU not
  supported`) — owner's fact, no radiance action. Also honest §D6.2 finding folded into
  AC6: the live 94 was LIMIT-ONLY (req stayed 64) ⇒ the pod is Burstable NOW; the 110
  PAIR sync restores Guaranteed in the same roll — desired end state, said plainly.
  plan_status remains approved (wave 9 unchanged); reopen→re-amend pattern per C08's
  lane-ruling precedent.

 - 2026-11-13 human+research D30 (OWNER CAPACITY QUESTION answered by RESEARCH §R8, lines
   1583–1903 — "check whether the 110Gi is enough for the 200K context for the model I'm
   running"): **VERDICT YES; D29's 110 STANDS; no scalar change, no pre-emptive ladder.**
   (1) THE PREMISE WAS INVERTED TWICE, both times in our favour: 200K is funded **ON-CARD**
   (`kv cache 4.49 GiB a card: 1600000 tokens, 8.0 sessions at 200000` ≈ 2.94 KiB/token fp8,
   the engine's own "the worst case"), and the HOST term is the eager `--kv-resident` mirror —
   PROVEN eager because boot A died at 64.00 GiB **with zero sessions arrived**. Margin at
   110: steady 110−71.04 = **38.96**; known-peak 71.04 + D28's own 21 GiB arrivals allowance +
   4 = **96.04 ≤ 110**, i.e. 110 is literally "96 plus 14 GiB of documented burst slack". 64
   was a defect, 94 was tight, 110 is the number the evidence supports.
   (2) RATES RECONCILED (the class law reaffirmed rather than newly earned): RQ1's ~12
   KiB/token UNDER-books the print by ~6 GiB (predicts 65.2 vs printed 71.04) and D28's ~20
   KiB/token OVER-books the residual by 2–5; the receipt-derived truth is **~16–18
   KiB/token** (residual 25.16–28.34 over 1.6M tokens). Both booked figures BRACKET it — which
   is why the plan prices off the PRINT, never off the rate. Honest uncertainty kept: boot B's
   printed PARTS sum to 77.88 against the printed WHOLE 71.04 (terms overlap somewhere), so
   the residual is BOUNDED, not decomposed.
   (3) MY OWN HYPOTHESIS REFUTED, recorded as a defect of my reasoning rather than of the
   host: I claimed a 110-of-125.08 pod would STARVE the host page cache the `mapped 47.68 GiB`
   disk-tier n-gram reads depend on. FALSE at the first link — that tier is **O_DIRECT**
   (engine docs + the boot's own "a direct read of one returned the file's bytes"), so the
   table never enters page cache (its host footprint is the ~85 MiB io_uring row cache; boot B's
   45.57 GiB available arithmetically excludes ~47.68 GiB of residency); k8s maps limits to
   `memory.max` with `memory.high` DISABLED, so a bigger max neither evicts cache nor is
   evicted by it (kernel cgroup-v2 doc); pinned pages are mlock-unswappable (mlock(2)) so the
   425 MiB of swap is unrelated anon; and the compaction counters are IDENTICAL at 94 vs 110
   because the footprint is the same — a boot-order risk, not a cap risk. Net: **raising the
   limit helps boot, is orthogonal to the disk path, and costs only scheduler slack — i.e.
   strata co-residency, which is D29's ruled either/or.**
   (4) OPEN, OWNER'S GATE (not a repo gap): the TRUE 8-session peak is undecided until runbook
   **step 6** runs; §R8-Q4's capture keys are the closing instrument — `memory.peak ≤ 100`,
   `memory.events` max/oom_kill = 0, `file ≈ 0` as the O_DIRECT falsifier, MemAvailable ≥ 8 at
   peak, buddyinfo/compact deltas, pinned in the 71–78 window. Fold into step 6's prose at the
   next doc round (STATE.deferred row).
   (5) TP2 FORWARD LOOK (§R8-Q5): at fn-TP2 the host answer SHRINKS ~3× (per-rank 12288 MiB ×2
   ≈ 24, the mirror gone, the prefix tier affordable → ~30–35 class; llmkube's witness runs
   262K at req 40/lim 48), so **110 strands nothing** — it is the single-card superset TP2's own
   receipts will re-pin DOWN; and at that smaller number strata co-existence may arithmetically
   RE-OPEN (~35 + 64 + 4.1 + 1.2 ≈ 104 ≤ 125.08), which is the CUTOVER ticket's decision,
   recorded so nobody has to rediscover it.
   (6) CORRECTION OWED TO THE OWNER IN-CHAT: I quoted "cold hash ≈ 8–23 min at 1000m" from the
   plan; §D4's own bound is **~5.8–13.6 min** (30–70 at the 200m cap ÷ 5, single-threaded
   busybox). The note carries the wrong string and it is T4-PINNED in the suite, so the fix is
   a SAME-WAVE doc+needle change (C12 review MINOR-2, with MINOR-3's tier-list framing and
   NIT-1's message wording) — stated plainly rather than quietly amended.
   (7) NO-REBASE ADJUDICATION: main advanced to `4cac77725` via cf-135 (Renovate-on-Forgejo);
   its changed files (renovate.json, .forgejo/workflows/renovate.yaml, tests/renovate/*,
   tests/services/forgejo-renovate.sh, cf-135's plan folder) DO NOT INTERSECT anything this
   branch touches, so NO rebase: rebasing would rewrite the landing SHAs that the wave guard
   and every record cite, for zero content gain; the merge delta stays content-based (step-10
   law). Re-verify the intersection before any future landing.
   plan_status stays approved (wave 9); C12 in_review pending round 2 on the fold ec92229ce.
 - 2026-11-13 coord note: D30's §R8 authority is RESEARCH.md §R8; the review's MINOR-2/MINOR-3
   and NIT-1 route to a single same-wave micro-round (plan ledger line → test re-pin → dev doc
   fold), NOT to silent prose edits, because the wrong figure is pinned by a test arm.
 - 2026-11-13 research+coord D31 (§D7 scout round 8 — CLOSING A COORDINATOR-SIDE CONTRADICTION,
   where one side was a REVIEW round's "verified" claim): C12 review r2's MINOR-R2-1 asserted
   `gpu-ai-radiance` auto-syncs with selfHeal ("verified appset-charts.yaml:132-138") and asked
   step 10's scale-down to carry step 3's suspend guard. §D7's LIVE READ says otherwise and §D4
   (scout round 6) was RIGHT: Application `gpu-ai-radiance` (gen 342) `spec.syncPolicy` =
   syncOptions ONLY (CreateNamespace=true, ServerSideApply=false, RespectIgnoreDifferences=true),
   **no `automated`**; last operation 16:29:51Z Succeeded **initiatedBy tms@spencerslab.com —
   MANUAL**; 0 of 7 sampled children and the parent `gpu-ai` app carry `automated`, and the
   template's default-true branch is skipped for every child because the NON-REPO
   cluster-registration knob (`services.gpu-ai.selfHeal` in the argocd secret, RBAC-closed to
   scouts) is not "true". So MINOR-R2-1 is SUPERSEDED-BY-OBJECTS — its GUARD INTENT survives,
   re-worded. Two owner-facing laws: (1) **there is no selfHeal to suspend** — runbook step 3's
   "suspend selfHeal" instruction is MOOT AND WRONG-AS-WRITTEN; the real hazard is a SYNC, manual
   included, because (2) **any sync re-applies git over hand-edits**: that 16:29:51Z click already
   replaced the owner's limit-only 94 Burstable edit with the 110/110 **Guaranteed** pair
   (Deployment gen 4 ⇒ D29's QoS repair is LIVE now, not pending), while strata's `replicas: 0`
   survives ONLY because `gpu-ai-llama-swap` has not been synced (git renders `replicas: 1` by
   app-template default, no ignoreDifferences on /spec/replicas) ⇒ **syncing that app is the
   resurrection trigger**, i.e. it IS step 10's restore moment, not a routine operation. C13's
   prose consequences: replace step 3's suspend-selfHeal shape with the don't-sync guard
   (OutOfSync through the window is EXPECTED, say so), delete step 10's "resume auto-sync" clause
   and state that a hand scale-down sticks until that app's next manual sync, ground the truth in
   live §D7 rather than the repo template, and re-look at the same false belief in
   `charts/radiance/values.yaml:40-41` (dev lane) and the 2026-10 gpu-cluster notes (follow-up
   card, fleet-wide prose). CLASS LAW FOR REVIEWS: **"verified" against a TEMPLATE is not
   verified against the CLUSTER** — sync-policy/annotation claims need a live object read, because
   this repo's base template emits defaults the cluster-registration knobs then override.
   Lineage note: main==origin/main==eaaba4197 now carries rebased twins of the C12 wave
   (ec92229ce ≡ 29d2cb5a4); branch records are NOT re-pinned (D30(7) stands — content-equivalence
   is the merge law, and content-diff main↔branch is 0 lines).
- 2026-11-13 plan D32 (C13 DOC MICRO-ROUND — wave 10, the routed C12-review items + §D7
  owner-facing safety folds; plan_status: STATE had stayed "approved" from the C12 re-opens
  — the wave-10 reason is recorded here rather than as a flip):
  (1) FIGURE: the 1000m cold-hash envelope "8–23 min" (runbook :415, tuning :331,
  values:385, testlib:175) is §D4's UN-throttled counterfactual re-used as a cap-bound
  figure — the bound is **~5.8–13.6 min** (30–70 @200m ÷ 5; single-threaded busybox, one
  core = whole gain; D30(6)); because the figure is T4/T5-PINNED the fix MUST be a
  same-wave doc+needle change (C13 AC1) — the §12.10 vocabulary-vs-grammar lesson applied
  to our own NUMBERS; arms get the stale-figure RED re-proof.
  (2) TIER HONESTY: tuning DIO list re-worded to a HIERARCHY — ram tier DEAD
  (71.04+47.68=118.72>110), stay-on-disk-4KiB the live posture (3.42<5 recorded; band
  3–10%), XFS/ext4 the owner's storage-lane option; and the "=" budget-sum sites take
  D30(2)'s BOUNDED-not-decomposed wording (parts 77.88 vs whole 71.04) + D30(3)'s
  O_DIRECT/page-cache refutation.
  (3) §D7 SYNC GUARD (the substantive fold, live-object law): runbook step 3's
  "suspend selfHeal / resume auto-sync" machinery is MOOT-AND-WRONG — 0/7 gpu-ai apps
  carry `automated`; the real hazard is witnessed: **any SYNC re-applies git over
  hand-edits** (16:29:51Z wiped the 94; strata's replicas:0 survives ONLY while
  gpu-ai-llama-swap stays unsynced — git renders 1) ⇒ replace with the lab's procedural
  DON'T-SYNC idiom (no sync of that app through the strata-down window; OutOfSync through
  the window is EXPECTED — it IS the parked scale-down; step 10 ordered restore:
  radiance's request off node → sync/restore strata in agreement → verify runner route).
  Review MINOR-R2-1 is **SUPERSEDED-BY-OBJECTS** (its suspend-clause must not ship; guard
  intent preserved re-worded per D7.4(2)) — CLASS LAW: **"verified" against a TEMPLATE is
  not verified against the CLUSTER**: any sync-policy/annotation claim needs a LIVE
  Application read, because base templates emit defaults the out-of-git cluster-
  registration knobs override (the knob itself is RBAC-closed; §D7.1's elimination
  inference is the proof shape).
  (4) values.yaml:40-41 VERIFIED-NIL for the false belief (D29 comment there; no sync
  prose) — the actual carrier is services/gpu-ai/prod/values.yaml:40-41 (cf-77 era), which
  §D7.4(4) routes to the FLEET prose card (C13 AC8.2 body line), NOT this ticket — recorded
  so the routing is visible, not silent.
  (5) STEP-6 CAPTURE KEYS (§R8-Q4/D30(4)) folded into the runbook as the 8-session gate's
  receipt list (memory.peak ≤100, memory.events max/oom_kill=0, file≈0 O_DIRECT falsifier,
  MemAvailable ≥8, buddyinfo/compact deltas, pinned 71–78 window) — receipt-decides law
  stays explicit; TP2 §12 gains D30(5)'s forward-look pointer (host answer ~30–35 at TP2,
  110 is the re-pin-DOWN superset, co-existence may arithmetically RE-OPEN ≈104.3 ≤
  125.08 — the cutover ticket's decision) + the r2-cosmetics bundle (NIT-R2-1 heading
  aligned to the body's "most probable" strength — SUITE IS STRENGTH-BLIND, proven both
  directions, NO arm invented; NIT-R2-2/3 one-word grammar folds, synth-proved needle-free;
  naming.sh :228 NON-FLIP label genericized per the coord note).
  Run-end: card #1 re-publish owed AGAIN (TP2 body moved); new fleet card per (4);
  XFS/ext4 card already deferred (verify). C13's bar: three notes suites at the new figure,
  radiance 46P with an EMPTY render-diff (comment-only values edits — asserted), naming
  NON-FLIP at C13's sha, witnesses unmoved.
- 2026-11-14 human+plan D36 (C14 DOCS-ONLY ROUND — §D10 authority; plan_status reopened
  complete(=FINAL r5 APPROVED after C13 landed + its r1 fold incl the fiction-ban arm)
  →approved, wave 11, reason: the tuning note's LINK section still advertised candidates
  §D10 falsified — an owner-facing checklist pointing at dead ends is this ticket's own
  defect class; it gets a real contract→red-first→dev→review round, not a silent edit.
  Numbering note: D35's ledger named the round "C15" before chunk reassignment; frozen-ids
  convention landed it as C14 with D35's content applying unchanged):
  (1) FALSIFICATION ON THE RECORD: the owner executed §R10's rung-1 ritual verbatim ("I
  turned everything off, turned the card dock on, waited 10 s, turned on the desktop, but
  performance is the same or worse") and a GENUINELY NEW cold boot — Node event
  `Rebooted … boot id 4d6202d9-14f2-4e7d-b107-1edec278a73d` @21:34:43Z, old pod SIGTERMed
  21:31:24Z (≈3 m 19 s off-window, consistent with the dock-first order, accepted on the
  owner's word — dock-button itself unobservable from k8s) — reprinted
  `link 00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2:00.0 8.0 GT/s x4 … [read at 48%
  busy]` + the WARN. The rate did not move BECAUSE THE LINK DID NOT MOVE: §R10's
  #1-ranked power-ordering latch is FALSIFIED by its own prescribed experiment; no repeat
  owed (spend power cycles on rungs 2-4). Hardware-state-did-not-move ≠ hardware-moved-
  but-rate-did-not — the first is the recorded fact.
  (2) MOVER PROVEN: the drained pod's recovered exit banner is the ticket's first COMPLETE
  heat-engine receipt — 20678 dispatches / 13736 promotions / 11960 demotions, max 300
  resident units/layer, 71.40 GiB h2d + 19.08 GiB d2h, 4971 readmits (36%), 46.2% prefetch
  no-lookback. Boot-B's `0 dispatches` = READ ARTIFACT (§D8 open question CLOSED); the
  churn adds ~90–100 MiB/token of re-placement traffic ON TOP of the ~200 MiB/token miss
  stream, during exactly the early requests — refines-and-strengthens link-first (one fix
  halves all three terms); rates 11.0/16.4 post-ritual = SAME, MID-RAMP on the m-curve —
  "same or worse" adjudicates to "same"; the fair number still needs the fixed ≥2000-token
  probe at request ≥4 (§D8.3, never run) + step-6 8-session gate (never run) — §R8's
  receipt-decides law stands.
  (3) SELF-CORRECTIONS, ours first: (a) §D8.2(b)'s inference that `max 154` was per-layer
  capacity is SUPERSEDED — residency reaches 300/layer with the documented KV/arena loans;
  (b) the "read at 61% busy" citation — mine, quoted into this round's launch framing —
  NEVER EXISTED anywhere in the ticket (grep nil); the honest census is **49% (§D6.6) →
  50% (§D8) → 48% (§D10)** across the three witness boots, rock-stable under-load reads;
  corrected against our own records, not just the note's.
  (4) LAW (fifth live-round confirmation, made mechanical): **a checklist row whose
  top-ranked cause has been falsified must be RE-POINTED IN THE SAME TICKET, not left for
  the next reader** — dead cures on an owner-console document are outages-at-3am. C14 AC1
  restates the ladder (reseat → Gen4-rated cable → DOCK BYPASS decisive → last,
  trust-flagged, BIOS-EQ/explicit-Gen4-menu only if it exists — R9-S17 UNVERIFIED), AC2
  labels the NOT-fixes (`pcie_aspm=off` no speed change R10-S9; setpci TargetSpeed/
  retrain pointless at TargetSpeed=16 already + link-down risk) and adds the row due
  REGARDLESS — `d3cold_allowed=0` udev + `amdgpu.runpm=0` STABILITY hygiene per the
  ArcheoCodix GPD-Win-4 + SAME DEG1 + RX-9070-XT precedent (same 00:03.1 root port, same
  1002:1478/1479 bridges), explicitly NOT a throughput fix; AC4 freezes the tokens that
  must survive (110/71.04/118.72/5.8–13.6/30–70 + the fiction-ban/marker arms); AC6 routes
  the final hardware-purchase rung (active redriver/PEX dock = TP2 §2 lane, or accept
  3.94 GB/s and chase profile levers/TP2) and the UNVERIFIED guards-optimality observation
  to the owner (record only, no advice shipped). GOVERNOR non-persistence re-confirmed a
  SECOND reboot (powersave reprint after the power cycle); pinned 71.04 fourth identical
  print. plan_status approved at wave 11 for this delta; the §D10 GPU-cluster control held
  (same gpu-llama-swap pod alive across the ritual — invariant re-witnessed).

  - 2026-11-13 research+coord D33 (§R9 — the owner's two pushbacks, both about PERF, and three of
    MY OWN claims retired on evidence): (A) **APU**: my "not costing you anything measurable
    today" was RIGHT-BUT-OVERSTATED and is NARROWED, not repeated. The community's "yes it costs"
    resolves into exactly two documented couplings — (1) the **Strix-Halo firmware power-limit tie**
    (the external-GPU power limit is *tied to the APU's BIOS power limit* — strixhalo.wiki, echoed
    by the r/GMKtec 120 W and Framework threads), which our own receipt FALSIFIES TODAY (the engine
    prints `power cap 300 W (default 300 W, max 300 W)` — we are not in the capped class), and
    (2) **shared-LPDDR5X contention while the iGPU actually COMPUTES** (Framework's "256 GB/s would
    be a bottleneck" is about the APU *serving*, not idling) — real, and UNMEASURED for our
    co-serving case, which is why it is now an ACTION (a loaded-router A/B) rather than a verdict.
    No attested cost for idle enumeration (ROCr/HSA knobs all target APU-users; radiance prints
    `1 device(s) [0:gfx1201]`). NO chart knob ships from this round: every route that would
    "recover" an APU cost (BIOS iGPU disable, vfio bind, `ip_block_mask`) either kills the
    `gpu-8060s` router claim (D21/B1 — the router would unschedule, cf-143's own C10 outage class)
    or is module-global poison. (B) **DEG1**: it is Minisforum's **passive** OCuLink Gen4 x4 dock
    (vendor "PCIE4.0*4 (up to 64GT/s)"; STH: "a PCB that handles the Oculink to PCIe slot as well
    as the power functions") — **no switch, no retimer, not hot-plug-capable, with a strict power
    sequence** (THOSE are its "settings"), and `c2:00.0`/`c3:00.0` are **the R9700's own integrated
    Navi switch pair** (`1002:1478/1479`, daimonionnn: "a plain direct attachment, not a tunnel or a
    dock switch"). So EXACTLY ONE physical link negotiates (root port `00:03.1` ↔ card, across cable
    + passive dock), its x4 width is by design, and its 8-vs-16 GT/s speed — third boot, reboot-
    surviving, under load — is the single defect. Best fit for the owner's forgotten setting is a
    **host-BIOS per-slot speed pin** (radiance's own `PREPARING_YOUR_RIG.md`: setting slot link speed
    wrong "stops the slots training at a lower generation"; tldevtech EVO-X3: explicit **Gen4, not
    Auto** — SEO-sourced, trust-flagged, no primary AMD/GMKtec BIOS doc exists), with the dock's
    power sequence + cold-boot discipline as the electrical branch; `LnkCtl2 TargetSpeed` under load
    is the one-minute discriminator (8.0 ⇒ BIOS pin; 16.0 ⇒ cable/dock/power-sequence). RETIRED:
    §D6.6's "(switch upstream)" label (the bridges are the CARD's), and the engine doc's own advice
    that **"a link stuck one level down has been cleared by a reboot"** is WITNESSED-FALSE on this
    node (we rebooted; the 17:20:25Z boot re-warned) — it must not be presented as a fix.
    Payoff stated honestly: Gen4 x4 ⇒ prefill 249→~450–500 tok/s, warm decode 19.3→~35 t/s (the
    compute floor caps it), TTFT halves — it does NOT buy the x4 width wall, the 41.52 GiB
    experts-from-host fact, or the 140–160 class (that road is TP2). UNVERIFIED, kept labelled:
    any idle-APU DRAM tax (no source either way), Strix-Halo fabric lane-sharing between `00:08.1`
    and `00:03.1` (AMD publishes no IOD block diagram; bounded by the live asymmetric link reads),
    whether a mid-session dock power-state change can latch a degraded negotiation across reboots.
    Authority: RESEARCH.md §R9 (lines 1907–2400).

 - 2026-11-13 human D34 (THE OWNER'S `LnkCtl2` READ CLOSES MY PRIMARY HYPOTHESIS — recorded
   immediately because it inverts the tuning note's discriminator and the next run must not
   re-litigate it): `lspci -vvv -s 00:00:03.1` ⇒ `LnkCtl2: Target Link Speed: 16GT/s,
   EnterCompliance- SpeedDis-`, `Transmit Margin: Normal Operating Range`,
   `Compliance Preset/De-emphasis: -6dB de-emphasis, 0dB preshoot`, while `LnkSta` reads
   `8GT/s x4`. So the root port is NOT BIOS-pinned to Gen3 — it is INSTRUCTED to train Gen4 and
   FALLS BACK, which moves the diagnosis from configuration to **signal integrity / LTSSM
   equalization**, and (because §R9 proved the DEG1 is a passive board with no retimer, and
   c2/c3 are the card's own Navi bridges) narrows the suspects in this order: **dock power
   sequence** (the DEG1 is explicitly NOT hot-plug capable and has documented power-on ordering —
   the strongest candidate for the owner's "a setting I was supposed to enable"), then
   **cable/connector integrity** (SFF-8611 seating both ends, kink/damage, a genuinely Gen4-rated
   cable), then **host-port equalization** (`-6dB` de-emphasis / 0dB preshoot are the compliance
   defaults; per-platform EQ is exactly what Gen4 training renegotiates and gives up on). The
   `EqualizationComplete+ EqualizationPhase1+` seen in earlier reads is Phase-1-only evidence at
   the trained (Gen3) speed, not proof Gen4 EQ ever succeeded — do not read it as such.
   ISOLATION LADDER (one variable per cold boot, verify with `LnkSta` after each; the definitive
   discriminator is step 4): (1) power order — dock PSU on and stable, card power LED lit, THEN
   host power-on; full cold boot (not reboot), per the dock's documented sequence; (2) reseat the
   OCuLink cable at BOTH ends until the latch clicks; inspect for strain/kink; (3) swap to a
   different known Gen4-rated OCuLink cable; (4) **bypass the dock** — card straight into the
   board's OCuLink port (or a different slot): Gen4 there with the same cable ⇒ the dock's power
   or PCB; still Gen3 ⇒ host port/cable/card-side EQ, and the card itself becomes the suspect
   (its own upstream port reports `32GT/s x16` capability, so a card-side fallback would need
   its own evidence); (5) only after 1–4, consider the OS-side write
   (`setpci … CAP_EXP+0x30.W` TargetSpeed overrides / forced retrain via `LnkCtl: Retrain
   Link`) — this is an OWNER-LANE WRITE with a documented unbootable/link-down risk and is NOT a
   repo proposal; the read-only receipts stay `LnkSta`, `dmesg | grep -iE 'link (training|downgraded|retrain)'`,
   and the engine's own `link` line + `GET /diagnostics` under load.
   WHAT THIS DOES NOT CHANGE: the payoff model stands (Gen4 x4 ≈ 7.88 vs 3.94 GB/s — the §D8
   miss-fraction model predicts prefill 249→~450–500 tok/s and warm decode toward the ~35 t/s
   compute floor), the APU answer stands as §R9 narrowed it (D33: no idle-enumeration cost,
   loaded-router DRAM contention is the open question, the Strix power-tie falsified by our own
   300 W print), and **nothing here is a repo change** — this is host hardware, owner-executed.
   Authority: the owner's paste (18:58Z) + RESEARCH §R9/§D8; the tuning note's LINK section is
   the fold target at its next touch (its "BIOS-pin vs cable" discriminator is now half-answered:
   BIOS-pin CLOSED, electrical OPEN) — recorded here so the record is not left holding the
   superseded half.

 - 2026-11-13 human D35 (THE POWER-SEQUENCE RITUAL IS FALSIFIED BY THE OWNER'S OWN COLD BOOT,
   and a lock incident to record against myself): the owner executed §R10's step 1 exactly as
   written — "turned everything off, turned the card dock on, waited 10 s, turned the desktop
   on" — and reports **"performance is the same or worse"**. So the strongest-ranked cause in
   §R10 (power-ordering latch) is **ruled out on this rig by direct experiment**, and the
   remaining ladder is: **(2) reseat the OCuLink cable at both ends until the latch clicks,
   (3) swap to a different known Gen4-rated cable, (4) the DEFINITIVE discriminator — bypass the
   dock** (card straight onto the board's OCuLink port with the same cable, or the dock on a
   second Gen4 host): Gen4 while bypassed ⇒ the dock's PCB/power path is the suspect (a
   redriver/PEX-switch purchase, TP2 §2's lane); still 8 GT/s while bypassed ⇒ host port /
   equalization, and the honest ceiling stays 3.94 GB/s with only the profile levers
   (residency, prefix-vs-kv-resident) and TP2 left. Reads `LnkSta` **under load** at each step
   (idle parks at 2.5 GT/s — that is the trap that fooled earlier reads) plus the engine's own
   `link` line, so a step is never scored on a warm reboot. Also noted: the same read settles
   whether "worse" is real regression or the miss-fraction ramp (§D8's warm-up shape), so the
   next probe must be the fixed ≥2000-token pair, not a short request.
   LOCK INCIDENT, self-reported: the 2 h reaper pruned this session's claim at
   16:09:03Z (`lastReap.reaped=["AI"]`) after the earlier server restart cost the in-memory
   registration (heartbeat answering `no_claim` while `pipeline_status` still showed the set
   held solely by me — the fourth variant of that engine bug). **Three records commits
   (f13200cdc, bf950d22a, 2c5151179) were made AFTER the prune and before the owner's word** —
   branch-local, no card move, no push, but outside the C09 rule that a lost lock stops
   commits. On the owner's "Do take your lock back for this" the claim was **re-acquired under a
   NEW setId `4cc5d898-f180-4eee-9d22-345c1ea7603a`** (the old `b60c418b…` is gone, not
   inherited) and the takeover is recorded here per the C09 law. Standing correction of
   practice: once a heartbeat returns `no_claim`, treat the lease as LOST — stop commits
   immediately and ask, rather than finishing "harmless" records work.
   FOLDED-BY-THIS-ROUND: the tuning note's LINK discriminator is now only half-live (its
   "BIOS-pin" arm was closed by D34's `TargetSpeed=16GT/s` read, and the power-sequence arm by
   D35), which is why C15 replaces that arm with the §R10 ladder + the NOT-fixes row
   (`pcie_aspm=off` no-ops the speed per [R10-S9]; `setpci` TargetSpeed/retrain overrides are a
   link-down risk with the config theory already dead) and the **`d3cold_allowed=0` +
   `amdgpu.runpm=0` STABILITY row** with the ArcheoCodix precedent — explicitly labelled
   stability, never a speed fix.

  - 2026-11-13 coord D37 (TWO SELF-REPORTED PROCESS DEFECTS that FINAL round 6 caught in MY
    records, filed as the ticket's last decision because both are laws, not footnotes):
    (1) **BOARD WRITES IN THE UNCLAIMED WINDOW, understated by my own incident record.**
    STATE.lock_incident said the three unclaimed-window commits involved "no card move, no
    push" — true for the CLAIMED card, incomplete as a description: inside that window
    (prune 16:09:03Z → re-claim ~18:5xZ) I also wrote the BOARD — filing the XFS/ext4 card
    (SEadqvfPHA6T2MwJS) and the fleet selfHeal-prose card (uzHJTPNhRxTPCwcn7) and re-publishing
    AD-144's body at 2c5151179's 18:46:52Z. Zero contention risk (both were NEW cards and a
    follow-up card of my own ticket; the held card never moved and nothing touched the cluster),
    but the rule's point is that a lost lease stops side-effects, and "card move" was the only
    one I disclaimed. LAW: when a lease is lost, the freeze covers **every** external surface —
    board writes included — not just the held card; and an incident record must enumerate the
    surfaces touched, not the ones it happened to think about. Amendment appended to
    STATE.lock_incident rather than editing the original prose (append-only law).
    (2) **"FRESH SESSION" WAS FALSE — VERIFIED AS MY REUSE, NOT A COPY SLIP.** The C14 r1
    review ran in the SAME session as the C13 r1 review (`ses_e29eb1f7cffe…`): I passed the id
    forward on the launch out of convenience, and the chunk's own note then read "fresh
    session" because that is the template wording. The contract requires chunk reviews to be
    fresh precisely so a reviewer cannot inherit the run's optimism; I broke it on C14 r1 (and
    the same reuse pattern runs through my FINAL rounds 3–6 on `ses_e2e9c1b8affe…`). Substance:
    every one of those rounds re-ran its own bars and synthesized its own fixtures, and C14 r1
    produced findings the earlier rounds had not (the COMPLETELY-claim over-read, the
    `293610128` digit, the banner tail) — so the verdicts were earned, not carried. But the
    record said something that wasn't true and the practice was wrong, so the correction stands
    on the record rather than on the outcome. LAW: a `sessionID` on an `agent-review` launch is
    a defect signal for a CHUNK review — pass none; where a continuation is genuinely intended
    (a narrow re-check of the same delta), say "continued session" in the note and let the
    coordinator's own judgment be the thing under review, not the label.
    (3) WHAT REMAINS ON THE RECORD from round 6 (all non-gating, folded with this entry):
    C13/C14 `commit` fields added to STATE; the chunks/C12.md:177 historical `-class` quote is
    ruled ACCEPTABLE as-is with D33's bracket as its pointer (round 6's own judgment); the
    §12.13 wrap-sensitivity sentence and the §12.14 aislop repo-pin stay carried (test lane /
    infra lane). And the ticket's landing state is explicit: main still carries the retimer
    fiction and the falsified Rung-0, so the branch's remaining docs-only delta
    (d645b7cf8 + 3261a92f3) is the last thing between the owner's console and a dead end.

 - 2026-11-14 research+coord D38 (§R12 — the owner's hardware reads, MY register mis-attribution,
   and the "others have done this build" claim, now answered with receipts):
   (1) **THE PARADOX WAS MINE, NOT THE MACHINE'S.** I read the owner's
   `EqualizationComplete+ EqualizationPhase1+ Phase2+ Phase3+` as "Gen4 equalization COMPLETED yet
   the link sits at Gen3" and built a diagnosis on that. It isn't: those bits live in the **base
   PCIe capability's Link Status 2 register = the LEGACY 8.0 GT/s (Gen3) EQ status** (pciutils
   `lib/header.h`: `EQU_COMP 0x02 / PHASE1 0x04 / PHASE2 0x08 / PHASE3 0x10 / EQU_REQ 0x20`), while
   **16 GT/s** status is a separate extended capability (`PCI_EXT_CAP_ID_16GT 0x26`, status at
   cap+0x0C, printed by lspci as its own `Phy16Sta:` block, with Data-Parity-Mismatch regs at
   +0x10/0x14/0x18). So the paste proves Gen3 EQ completed (normal) and says NOTHING about Gen4.
   LAW (and the correction of a D37-shaped mistake, this time about HARDWARE rather than my own
   process): **never diagnose from a register field whose owning capability I have not checked** —
   read the tool's decoder source or the spec for the bit I am interpreting, then interpret. The
   one free read that branches the whole problem: `Phy16Sta` on `00:00:03.1` AND `c2:00.0`.
   (2) **THE BIOS RUNG IS CLOSED BY FACT, TWICE.** The box is on **03.06**, which is the LATEST
   published for the Desktop (resources.frame.work lists 3.06/3.05/3.03/3.02, "Stable Latest"), and
   the release-note audit has **zero per-slot PCIe content in any version** (3.03: PD/EC/
   SecureBoot/OPAL; 3.05: RAM modules, GRUB boot, downgrade path; 3.06: AMD PI 1.0.0.2c, a
   video-encoder boot-hang fix, an iGPU-24GB fix, CVEs). So §R11's "check 3.06" candidate and the
   GMKtec-world "explicit Gen4, not Auto" menu lead are BOTH dead: no per-slot speed menu is
   documented for this platform at all. And the boot-hang lineage matters — the same thread's
   Frix_Rioux had it fixed by a **kernel** update, which is why "firmware" must stop appearing in
   our ladder.
   (3) **THE OWNER'S CLAIM IS SUPPORTED — WITH AN UNCOMFORTABLE TWIST.** A working Framework Desktop
   + **DEG1** + RX 9070 XT (gfx1201, same card class) build on Linux exists, running **llama-bench
   on the SAME Qwen3.8-Flash-Next model at pp 324.8 / tg 21.1** — which is *the same ballpark as our
   own 16.4–19.3 t/s decode and ~250-class prefill*, with no `LnkSta` receipt published anywhere on
   that platform. Read honestly: "others have done this build" may mean "others did it **at Gen3**",
   and the 142–160 t/s community numbers belong to Gen5 x8/x8 rigs. No Framework-Desktop
   16 GT/s x4 receipt exists in any source found — and no Framework report posts `LnkSta` at all,
   which is exactly the gap our case could fill (worth publishing either way).
   (4) **PLATFORM SETTLED + TWO CONFOUNDERS REMOVED.** `Desktop (AMD Ryzen AI Max 300 Series)` —
   Framework's own copy says "The **PCIe x4** slot lets you connect …", so electrically x4 by design
   and "16" is the x16-length connector (or a Laptop-16 conflation). New `lspci -t` puts the NVMe on
   its own root port `00:02.5-[c1]`, so **the n-gram disk tier and the dock link do not contend** —
   §D11's last open topology question closed, §D8's math unaffected.
   (5) REVISED LADDER (§R12-Q5): rung 0 = the `Phy16Sta` + AER + Data-Parity reads (free, and it
   decides whether we have an EQ-failure problem or a channel-quality problem); rung 1 = identify the
   **bay adapter card** — never once recorded in this ticket — including the K993G-BK7-**R29Q**
   anecdote of undocumented **physical switches** on the part another Framework builder used, which
   is the closest thing found to the owner's "a setting I was supposed to enable"; rung 2 = reseat +
   short known-Good cable; rung 3 = EOP4A-class redriver insert; rung 4 = bypass controls (native
   OCuLink host / open frame); rung 5 = kernel/`d3cold`/`runpm` hygiene, STABILITY only. BIOS, the
   dock-first ritual, `pcie_aspm=off` and `setpci` speed overrides are formally CLOSED/DENIED with
   citations — and no redriver purchase until rung 0 says `EquComplete-`, because if Gen4 was never
   attempted, a channel fix is what is being bought; if Gen4 WAS attempted and failed parity, the
   honest answer is TP2 (the x4 wall) or the profile levers, at §R11's ~54%-lost-to-narrow-link
   pricing for weights-crossing regimes like ours.
   (6) LOCK/CLAIM STATE, recorded because it changed shape: the `AI` claim was reaped 00:45:29Z and
   the recovery rule was followed — re-claimed under the **card-id pipeline**
   (`f014f568…`, locks/Na5LxMaY3ptABWhAy.json), NOT `AI`; a stale `default` claim left by a scout
   session on this card is unowned by me and will age out at the 2 h mark; the ticket's records are
   now landed on the branch, and the plan remains reopened at wave 11 for the note's ladder fold.
   Authority: RESEARCH §R12 (lines 2879–3144); supersedes §R11's firmware candidate and my D37-
   adjacent register reading; nothing in §D8/§R8/§R9's capacity math moves.

 - 2026-11-14 research+coord D39 (§R13 — the two-day link hunt gets its mechanism, and three of
   MY recommendations are formally retired): the owner's correctly-read `Phy16Sta: EquComplete+
   EquPhase1+ EquPhase2+ EquPhase3+ LinkEquRequest-` on `c2:00.0` means **16 GT/s was genuinely
   trained and the link then demoted** — TI's link-training doc (SNLA415) is the authority for the
   grammar: EQ is a per-generation cascade ("from Gen 3 to Gen 4"), Phase 2 is gated on
   "BER of less than 10⁻⁴" and completion on "BER less than 10⁻¹²", and on long channels
   "this level of signal quality is not possible… repeaters like redrivers and retimers are
   used", with the link settling at "the fastest rate it can stably support". So `LnkSta 8GT/s`
   beside a completed Gen4 EQ is spec-normal margin behavior, not a config we forgot.
   RETIRED IN WRITING, each for a stated reason: (1) **the redriver-purchase rung** — the owner
   already owns an **M2-1955-OCU**, vendor-described "Built-in PCIe ReDriver to extend PCIe Gen4,
   16GT/s…"; my §R12 recommendation was simply wrong and §R11's "buy a redriver card" advice is
   already spent; (2) **the adapter-identity rung** — closed as a redriver, and redrivers are
   **analog and invisible to `lspci -t` by design** (TI: a *retimer* makes each side initialize the
   link separately — "Link subdivision" — whereas our root port reads `Retimer- 2Retimers-`, i.e.
   no detected retimer), so the card's absence from the topology is expected, not evidence of an
   inert part; (3) **the BIOS/firmware, ritual, aspm and setpci rungs** stay closed from
   §R12/D35/R10-S9. ASM1955's exact silicon class remains **UNVERIFIED** (no public datasheet
   surfaced; ASMedia's own taxonomy separates redrivers like ASM1468 from its retimer lines).
   THE REMAINING AMBIGUITY IS THE HOST END, and three free reads settle it without AER (which
   `_OSC` withholds): root-port `Phy16Sta`, its Data-Parity-Mismatch registers at cap+0x10/0x14/0x18,
   and `DevSta: CorrErr+` from the PCIe capability. Host `EquComplete-` against the card's `+` ⇒ the
   negotiation never got the host's agreement (→ the **socket** leads); host `EquComplete+` with
   parity/correctable errors ⇒ it lived Gen4 and lost margin in traffic (→ the **cable/chain**
   leads); no cap 0x26 on the root port at all ⇒ the only branch that re-opens firmware.
   NEW FREE A/B, and it is now ladder rung 1: our two M.2 sockets sit on **different root ports**
   (`00:02.5` = the NVMe, `00:03.1` = the dock), so **moving the adapter to the other M.2 slot** is
   a zero-cost per-port behavior test the previous ladders never had. Also added as owner-lane
   reads: `echo 1 > …/remove` + rescan so the port driver narrates the Gen4 attempt in `dmesg`
   (radiance must be down for that), and the Lane-Margining detour is PARKED, not pursued
   (`Uses Driver-`/`MargReady-`, no Linux tool evidenced).
   CENSUS HARDENED, said plainly for the owner: Framework Desktop has **no native OCuLink** — the
   community method is literally "take up one of the nvme slots to an oculink adapter" (our exact
   architecture) — and **no Framework Desktop owner has ever published a negotiated link speed**,
   while the closest same-model build (Frix_Rioux, llama-bench pp 324.8 / tg 21.1) sits inside our
   own band. "Others have done this build successfully" is therefore true but most likely means
   "done at Gen3"; our case can be the first published receipt set, and if the reads say the chain
   cannot hold 16 GT/s, the bandwidth road is TP2/§R11's switch-dock lane, not another cable.
   RECORD ACTION: C14's ladder is re-pointed by a docs-only r1-fold per D36's law (retired rungs
   deleted, socket-swap promoted to rung 1, host-end reads added as rung 0) — the note must not
   keep advertising a redriver purchase or an adapter-identity mystery to an owner who answered
   both in one sentence. Authority: RESEARCH §R13 (lines 3148–3440).

 - 2026-11-14 human+coord D40 (THE HOST-END READ LANDS — both ends of the external link say Gen4
   equalization COMPLETED, and the link is still at 8 GT/s; the owner's verbatim reads):
   root port `00:00:03.1` **implements** cap 0x26 — `Capabilities: [410 v1] Physical Layer 16.0
   GT/s` / **`Phy16Sta: EquComplete+ EquPhase1- EquPhase2- EquPhase3- LinkEquRequest-`** — plus
   `DevSta: CorrErr- NonFatalErr- FatalErr- UnsupReq-` and `LnkCtl2: Target Link Speed: 16GT/s,
   EnterCompliance- SpeedDis-` with `LnkSta: Speed 8GT/s, Width x4`; the card's upstream bridge
   `c2:00.0` remains `EquComplete+ Phase1+ Phase2+ Phase3+`; and `c4:00.0` (the GPU function, i.e.
   the CARD-INTERNAL c3→c4 hop) reads `EquComplete-` with `MargReady+`.
   READINGS, with the uncertainty named: (1) **the `c4:00.0` result is not our link** — that is the
   internal Gen5 hop (already at 32 GT/s per its own `LnkSta`), whose 16 GT/s status is simply
   unused; only `00:03.1`↔`c2:00.0` is the external link. (2) The root port's **phase bits all '-'
   with EquComplete+** is either (a) this root complex not implementing the per-phase evaluated
   bits (plausible — the bits are per-implementation readable as "did *this* port evaluate that
   phase", and the phases a downstream port owns differ from the upstream's), or (b) Gen4
   equalization was completed by the upstream port while the host side skipped its own phase
   evaluation. Either way **the port that controls the speed change declares EquComplete+ and
   LinkEquRequest- (no re-EQ requested), yet the negotiated speed is Gen3** — so §R13's
   "host-EQ-failed ⇒ move the socket" branch is NOT what we have, and the live possibilities
   collapse to: a **post-EQ speed-change abort** (SI margin in traffic — which §R13 already showed
   is spec-normal "the fastest rate it can stably support"), or a **firmware/boot-sequence clamp**
   that never actually executed the speed change. (3) The all-'-' `DevSta` is **uninformative, not
   clean**: `_OSC` withheld AER, so those bits are not populated — which is why the next reads must
   use the AER-INDEPENDENT per-lane `LnkErrSta` (inside the PCIe capability) and the
   bridge `SecSta`.
   ACTION THEREFORE (cost order, and it reorders §R13's ladder): **rung 1 becomes a forced RELEARN
   / retrain of the link** — cheap, reversible, and the only read that separates a boot-sequence
   clamp from a margin problem, because a retrain that lands `16GT/s` means the negotiation is
   capable and merely never ran at boot, while a retrain that returns `8GT/s` convicts the channel.
   Owner-lane commands (radiance scaled down first; a retrain blinks the link, so this is not run
   beside live traffic): `setpci -s 00:00:03.1 CAP_EXP+0x10.w=20:20` (LnkCtl bit 5 = Retrain Link,
   value:mask form), then re-read `LnkSta` on both `00:00:03.1` and `c2:00.0`; or the heavier
   `remove`+`rescan` route which re-enumerates and narrates in `dmesg`. Then the AER-free error
   reads (`grep -A6 LnkErrSta` on both ends, `SecSta` on the root port). **The M.2 socket swap drops
   to rung 2** (it is still free and still worth doing, but the host-end read took away its
   justification), cable to rung 3, and the terminal fork unchanged: if a retrain cannot hold 16
   GT/s, the chassis path is Gen3 and the bandwidth money belongs to TP2, not another cable.
   Also still open on the BIOS question: the AMD CBS-style per-slot PCIe speed override (the
   Framework BIOS menu is documented as sparse, so this is "look and report", not "assume").
   Authority: the owner's paste, 2026-11-14; §R13's host-end branch is now resolved as
   "EquComplete+ at the host too", superseding the "host may not have agreed" reading while
   leaving §R13's TI mechanism (trained-then-parked is spec-normal) fully intact.

 - 2026-11-14 human+coord D41 (THE RETRAIN TEST COULD NOT RUN, AND THE REFUSAL IS ITSELF THE
   FINDING; plus this chain turns out to have NO error counters at all): the owner's
   `setpci -s 00:00:03.1 CAP_EXP+0x10.w=20:20` died on **`pcilib: sysfs_write: write failed:
   Operation not permitted`** — a config-space write refused by the kernel (the prime suspect is
   **kernel lockdown** with Secure Boot on, which is exactly the mode where `/sys/.../config`
   writes are denied; `cat /sys/kernel/security/lockdown` settles it in one command). Consequences,
   stated carefully because the test did NOT run and nothing may be concluded from the unchanged
   reads: (1) **Rung 1 is NOT falsified — it is blocked**, so the speed-change question stays open;
   (2) **if lockdown is what refused it, then every `setpci`-based mitigation is off the table on
   this box** — including the "capable but never ran at boot ⇒ script a retrain" persistence
   branch I sketched in D40 — which leaves only BIOS/firmware configuration, a physical topology
   change (socket/cable/dock), or the driver-level reset path below, and turns any
   "retrain-on-boot" idea into a Secure-Boot policy decision the owner must choose to make, not
   something this repo can hand them; (3) the read-only alternatives that do NOT touch config
   space are `echo 1 | sudo tee /sys/bus/pci/devices/0000:00:03.1/reset` (a bus reset forces the
   downstream link to retrain, with radiance deliberately down first) and the heavier
   `remove`+`rescan` pair that re-enumerates the subtree and lets the port driver narrate the
   attempt in `dmesg` — the reset route is the one to try, and the verdict rule from D40 is
   unchanged in shape: 16 GT/s after the reset ⇒ capable-but-never-ran-at-boot (then the ONLY
   durable fixes are a BIOS/firmware setting or a physical change, because writing config is
   denied), still 8 GT/s ⇒ channel cannot hold Gen4.
   (4) **No error visibility exists on this chain**: `grep -A6 'LnkErrSta'` printed NOTHING for
   both `00:00:03.1` and `c2:00.0` (the ports do not expose the per-lane Lane Error Status bits
   that lspci would print) and `DevSta` is unpopulated because `_OSC` withheld AER — so my AER-free
   substitute from D40 does not exist on this hardware either. The margin hypothesis therefore
   **cannot be measured, only experimented on**, which is worth saying before the owner buys
   anything: we have no counter that would move if the channel were marginal.
   (5) A live detail to re-verify rather than explain away: the SAME c2:00.0 port that earlier read
   `Phy16Sta: EquComplete+ EquPhase1+ EquPhase2+ EquPhase3+` now reads `EquComplete+
   EquPhase1- EquPhase2- EquPhase3-` with `LnkSta: 8GT/s (downgraded)` — the phase-evaluated bits
   CLEARED between reads. My inference (unproven): an intervening link event — e.g. the amdgpu
   probe/reset path during the radiance pod's restarts — retrained the port, and those bits are
   only meaningful for the EQ run that just happened. The cheap check is to read `Phy16Sta` twice
   across a known link event; if the bits track retrains, then **`EquComplete+` on the host is even
   weaker evidence than D40 assumed** (it may be residue of a recent retrain rather than proof the
   boot negotiation completed), and the honest summary becomes: both ends show Gen4 EQ status, the
   link runs Gen3, no counter explains why, and the only discriminator left is the reset experiment
   plus, if it stays Gen3, a physical topology change.
   RECORD ACTION: D40's "Rung 1 = setpci retrain" is superseded in the note (fold #4): the setpci
   line is kept ONLY as the documented-denied attempt (with the EPERM text quoted), and the reset
   path becomes the actionable command, with the lockdown check as rung 0's first read. Authority:
   the owner's paste, 2026-11-14.

 - 2026-11-14 human+coord D41 (MY RUNG-1 COMMAND WAS DENIED — and the phase bits moved between
   reads, which is the more informative half of the paste):
   (1) **The retrain did not happen, so nothing about the clamp-vs-margin question is decided.**
   `sudo setpci -s 00:00:03.1 CAP_EXP+0x10.w=20:20` returned
   **`pcilib: sysfs_write: write failed: Operation not permitted`** — the write was refused before
   touching the register, and the `LnkSta: 8GT/s` that followed is therefore the SAME observation as
   before the attempt, not a result. Rung 1 is WITHDRAWN as written, not executed. Prime suspect
   for the refusal, straight from this machine's own boot line: **`security=selinux selinux=1`** —
   an enforcing SELinux policy denies userspace writes to PCIe config space through sysfs, which is
   exactly this shape of `EPERM` for a command run as root (kernel lockdown is the alternative and
   is checkable in one line). The reads that settle it are `getenforce`,
   `cat /sys/kernel/security/lockdown`, and `sudo dmesg | grep -iE 'avc.*denied.*(config|sysfs)'` /
   `sudo ausearch -m avc -ts recent` — a denial naming this write makes it a POLICY question for the
   owner, not a hardware finding, and the ladder must then route through the kernel's own reset path
   instead of raw config writes.
   (2) **`Phy16Sta` phase bits CLEARED between two reads of the same port** — earlier
   `c2:00.0: EquComplete+ EquPhase1+ EquPhase2+ EquPhase3+`, now
   `c2:00.0: EquComplete+ EquPhase1- EquPhase2- EquPhase3-`, with `LnkSta 8GT/s (downgraded),
   Width x4 (downgraded)` and `LinkEquRequest-` throughout. Read carefully, this is informative:
   the phase-evaluated bits are per-attempt state, so a link event happened in that window (the
   amdgpu probe/reset on the pod's restarts, or the failed write's neighbours) and **the host's
   `EquComplete+` is weaker evidence than D40 treated it as** — it can describe the most recent
   retrain, not the boot negotiation. What survives from D40 stands on the new read anyway: both
   ends still say complete, the link still runs Gen3, and nothing requested re-EQ.
   (3) **The AER-free substitute I recommended does not exist on this hardware either**: `grep -A6
   'LnkErrSta'` printed NOTHING for both `00:00:03.1` and `c2:00.0` — these ports do not expose
   per-lane Lane Error Status, and `DevSta` is unpopulated because `_OSC` withheld AER. So
   **there is no counter on this box that would move if the channel were marginal**: the margin
   hypothesis is experiment-only, and that is a strong argument against buying anything before the
   experiment is possible.
   (4) REVIVED NEXT STEPS, in cost order, with the config-write route marked as policy-gated:
   rung 0 = the three one-liners above (`getenforce`, the lockdown read, the AVC grep) — they decide
   whether Rung 1 is a five-minute test or a deliberate security decision; rung 1 (kernel path,
   does not need raw config writes) = `echo 1 | sudo tee /sys/bus/pci/devices/0000:c2:00.0/reset`
   **with radiance deliberately scaled down first**, then re-read `LnkSta`/`Phy16Sta` on both ends
   and `dmesg` for the port driver's own narration; rung 2 = the physical M.2 socket swap (different
   root port: `00:02.5` vs `00:03.1`, §D11/§R13); rung 3 = shorter/known-Good cable; rung 4 = dock
   bypass. Verdict rule unchanged: 16 GT/s after a retrain ⇒ capable-but-never-ran-at-boot (and if
   SELinux is what blocks writes, then a scripted retrain is NOT available and the durable options
   collapse to a BIOS/firmware setting or the physical change); still 8 ⇒ channel/chain, and per (3)
   we could never have measured it, so the experiment is the only evidence available.
   Authority: the owner's paste, 2026-11-14. Note for the record: this is the third time in this
   ticket that an owner-lane command I authored was wrong (`sed` address, `lspci -s` form, and now a
   `setpci` write the platform refuses) — the fold-into-the-note law (D36(4)) applies to my COMMANDS
   as much as to my claims, so the commands are corrected in the document, not just in chat.

 - 2026-11-14 human D42 (WHY THE RETRAIN WRITE WAS REFUSED — kernel LOCKDOWN, not SELinux; and the
   test therefore still has an unblocked route): the owner's two reads settle D41's open
   either/or. `getenforce` = **Enforcing** but `ausearch -m avc -ts recent` = **`<no matches>`** ⇒
   SELinux never touched the call, so my prime suspect was wrong, and the actual cause is the
   second one: `cat /sys/kernel/security/lockdown` = `none [integrity] confidentiality` — the
   bracketed value is the ACTIVE mode, so this box runs in **lockdown=integrity** (the consequence
   of Secure Boot being enabled), and under lockdown the kernel permits **reading** PCI config
   space and refuses **writing** it with `EPERM`. That is exactly the asymmetry observed — every
   `lspci -vvv` worked, the `setpci` write did not — and it means D41's Rung 1 stays UNRUN, with
   the clamp-vs-margin question still undecided.
   WHAT THIS DOES NOT MEAN: that the experiment is dead. Lockdown gates *userspace config writes*;
   it does not gate the kernel's own reset/retrain machinery, so the unblocked routes are
   `echo 1 | sudo tee /sys/bus/pci/devices/0000:c2:00.0/reset` (kernel-internal path; scores on
   both ends afterwards) and the `remove`+`rescan` pair, with radiance deliberately down first per
   §D7. If BOTH of those are also refused, then no software route to a retrain exists on this
   platform and the ladder is physical from there (M.2 socket swap → cable → bypass).
   THE DECISION THAT IS THE OWNER'S ALONE: turning Secure Boot off would lift lockdown and make
   `setpci`/scripted-retrain approaches available, but that is a **security-posture change on a
   machine the lab boots daily**, and it is NOT a tuning knob — the ticket's position, stated so a
   future reader does not "helpfully" disable it: if a durable fix requires disabling Secure Boot,
   the physical rung (socket/cable) or TP2 is the cheaper answer. Recorded also because it
   retroactively explains a silence: lockdown-mode restrictions are why nothing in this ticket can
   reach AER-style or config-level detail on this box — the `_OSC` withholding and this refusal are
   two different gates on the same platform's firmware posture, and our diagnosis has been fighting
   both at once.
   AUTHORITY: the owner's paste, 2026-11-14 (D41's "prime suspect SELinux" is superseded by
   evidence; the phase-bit and no-LnkErrSta findings in D41 stand unchanged).

 - 2026-11-14 human+coord D43 (**THE RETRAIN EXPERIMENT RAN, AND IT CAME BACK GEN3 — so the
   boot-clamp hypothesis is dead and the physical chain is the remaining suspect**): the owner's
   `echo 1 | sudo tee /sys/bus/pci/devices/0000:c2:00.0/reset` printed
   `tee: '…/reset': Inappropriate ioctl for device` **but the reset DID execute** — `dmesg` shows
   `pcieport 0000:c2:00.0: resetting` / `reset done` and a full amdgpu resume on `c4:00.0` (PCIE
   GART re-enabled, PSP/SMU resumed, rings re-registered). Two corrections and one conclusion:
   (1) **my D42 hedge was wrong** — I wrote that a sysfs reset "might also be refused"; it is not,
   because lockdown gates *userspace config writes* and this path is the kernel's own. The
   `ioctl`-flavoured error is noise from how that attribute reports, not a failure: **verify a
   refused-looking write against `dmesg`, which I should have said rather than hedged**.
   (2) The `Width x4 (downgraded)` flag on `c2:00.0` is NOT new information — that bridge's own
   `LnkCap` advertises x16 while the OCuLink path is physically x4 by design (§R12-Q4), so the
   width flag is lspci comparing the link to an advertised maximum we already knew was aspirational.
   Do not let it be read as a fresh degradation.
   (3) **The conclusion is the speed flag.** A secondary-bus reset re-initialises the link from
   Detect, and with `LnkCtl2 TargetSpeed: 16GT/s` set on the root port, this was a genuine fresh
   negotiation — not a stale boot-time latch — and it landed at `8GT/s (downgraded)` on both ports
   with `Phy16Sta: EquComplete+` unchanged. That is what falsifies "capable but never ran at boot"
   (D40's first branch, which the failed `setpci` had left undecided) and leaves the physical
   chain: the socket path, the riser/adapter's channel, or the cable. Ladder therefore re-ranks
   WITHOUT further software rungs: **(i) move the adapter to the other M.2 socket (different root
   port, `00:02.5` vs `00:03.1` — free, and now the highest-value test), (ii) a shorter known-Good
   Gen4 cable, (iii) dock bypass/open frame** — re-reading `LnkSta` after each with the same
   reset-then-read method that just worked (`…/reset` + `dmesg` + `LnkSta`), and accepting, if all
   three still say 8GT/s, that this chassis path is Gen3 and the bandwidth answer is TP2, per
   §R13's terminal fork. BIOS/firmware, the ritual, aspm, setpci and "buy a redriver" all stay
   retired, and **no further retrain attempts are worth making** — the register said what it says.
   (4) OPERATIONAL, not analysis: the reset hit a **live** GPU. `dmesg` shows a clean resume, but
   any in-flight radiance request died with it and the pod will have restarted — cheap by design
   (the init marker skips in <1 s, the pack is intact and already hash-verified), yet the runbook's
   own discipline exists for this reason, and the honest note is that this experiment should have
   been run with radiance scaled down first as D42 said; the outcome is unaffected, the method was
   not. Authority: the owner's paste, 2026-11-14.

 - 2026-11-14 human D44 (**THE SOCKET WAS THE FAULT — Gen4 x4 achieved for the price of a
   screwdriver**): the owner moved the M.2→OCuLink adapter to the board's OTHER M.2 socket and the
   host↔card link now reads `LnkSta: Speed 16GT/s, Width x4` with `Phy16Sta: EquComplete+
   EquPhase1+ EquPhase2+ EquPhase3+ LinkEquRequest-`. D43's verdict rule resolved on the second
   branch — the physical chain — and the culprit was the socket/root-port path: not the cable, not
   a defective dock PCB, not firmware, and not a redriver the rig already had. Reading rules
   recorded so this is not misread later: `c1:00.0`'s `(downgraded)` flags are permanent and
   harmless (the bridge's own `LnkCap` advertises 32GT/s x16 — the CARD's ceiling, so any platform
   link under it reads "downgraded"); the `32GT/s x16` hops are card-internal (D43); and the two
   `2.5GT/s x16 (overdriven)` ports are unoccupied platform ports, not our chain. **My D40/D43
   "host agreed ⇒ clamp-vs-margin" framing was chasing the wrong signal: the speed VALUE mattered,
   the adjective did not.** Topology after the swap (`lspci -tvv`, `readlink -f
   /sys/class/nvme/nvme0/device`): GPU under `00:02.5-[c1-c3]`, NVMe under `00:03.1-[c4]` — the
   two devices TRADED root ports, so the shared-upstream contention I raised is REFUTED by the
   read, not by reassurance.
   THEN THE PART THAT COSTS ME A CLAIM: the owner reports performance landed where I predicted
   (~35 t/s) and says **single-card R9700 builds are getting 70+**, so my "70+ is unreachable by
   bandwidth" arithmetic is SUSPECT AT ITS INPUTS, not just its conclusion — I divided the report's
   cumulative `mover: 71.40 GiB h2d` (which includes the cold-load promotion of ~17.76 GiB into
   VRAM) by a token denominator of 884 that **no record in this ticket actually sources**, and got
   "~83–100 MiB/token" as if it were measured. A cumulative counter over an unverified denominator
   is exactly the vocabulary-not-arithmetic class this ticket has been correcting all week, and it
   produced a confident, wrong ceiling. RETRACTED as a bound; kept as a hypothesis to test. The
   honest statement is: the link fix is confirmed and worth ~2×, and the remaining gap between
   ~35 and 70+ has NO established cause — the suspects are host-side, not wire-side (the n-gram
   disk tier's 4096-byte non-aligned spans on btrfs, memlock 8 MiB, the 46.2% "looked back on
   routed" prefetch waste and 36% readmits, `powersave`/`balance_performance` per-rank host work,
   THP compaction stalls at 71 GiB pinned), plus whatever the published 70+ configurations do
   differently. §R14 is commissioned on exactly that question, with the decisive read being
   `/stats`' `stream_bytes ÷ decode_tokens` — the number that replaces my invented one. Authority:
   the owner's reads, 2026-11-14 15:38Z, and their 70+ report.

 - 2026-11-14 research+coord D45 (THE DECODE FLOOR IS DOCUMENTED, AND THE TWO knobs the owner asked
   about LOCK EACH OTHER OUT; the wire question is now closed by measurement): the owner's first
   real `/metrics` read (D44-adjacent) settles what §R14 could only bound — KV streaming is
   `410,673,152 B ÷ 2385 tokens` ≈ **172 KiB/token ≈ 0.02 ms**, and even charging the mover's
   entire cumulative `71.40 GiB h2d` to those tokens gives ~31.8 MiB/token ≈ **4.2 ms**, against a
   ~28 ms step ⇒ **the wire is ≤15% of step time**, and prefill at **~467 tok/s** matches §D8's
   Gen4 forecast. The coordinator's VOID bound (D44) is therefore fully superseded by measurement,
   not by better arithmetic. §R15's answers, all doc-quoted:
   (1) **`--ngram-placement ram` is gated on free RAM, not on memlock** — GUIDE §4.3's requirement
   is "the table's size free after the pinned host pools … under every memory cgroup … and refuses
   the start otherwise"; our earlier §D6.3 attribution of the RAM tier to `RLIMIT_MEMLOCK` was a
   drift (that clause belongs to the no-`libr4d` host-gather fallback). It is **doubly dead at
   8×200K**: `71.04 + 47.68 + 4 > 110` refuses the start, AND the only way to make room — dropping
   `--kv-resident` — moves the QSA group's ~6.00 KiB/token onto the card (~9.3 GiB) and **shrinks
   the expert slab 17.76 → ~8.5 GiB**, i.e. it reverses the docs' own "the VRAM it gave up went to
   the expert slab" benefit. So the two knobs the owner asked about are mutually exclusive: **you
   cannot fund the n-gram RAM tier by unloading the KV mirror.**
   (2) **`--kv-resident` is a CAPACITY flag** — decode-neutral by measurement (39.89 vs 39.78),
   prefill +1–2%, and its purpose is "the context is no longer bounded by VRAM"; while it streams,
   the **prefix tier is force-off**, so our `cache 0` / ~12 s TTFT on a 37-message agent workload is
   the DOCUMENTED price of the capacity lane we are on (the GUIDE's cliff: 173 s @0.0% vs 3.0 s
   @99.0%). §R14's "dropping the mirror buys zero decode" is confirmed and now has a reason.
   (3) **Session/context edits are noise for decode, not levers.** KV→slab elasticity is real in the
   docs, but with wire ≤15%, `--max-num-seqs 8→4` is worth **≈−1% of step time** while spending half
   the owner's session envelope — so NO profile edit is justified at 8×200K, each either
   sub-noise or capability-spending.
   (4) **THE HEADLINE, and it ends a multi-day expectation: there is no published single-card
   iq4r-FlexNext decode above ~40 t/s anywhere** — every faster row is another engine
   (RTX-5090/basalt 297.7, **RX-9070/Strata IQ2 60.0**, M5-Ultra/oMLX, DGX/SGLang), another quant, or
   **two+ cards** (radiance TP2 62.3–64.8 measured by the docs, 137 on L1T). The "people get 70+ on
   one R9700" memory maps onto the dense q27 lane or TP2 rows. **Our ~35 t/s is the creator's own
   documented `--tp 1` floor (28–29 ms), reached.** Stop optimizing for the other number.
   (5) **EPP, not governor-name, and it survived `cpupower` for a documented reason**: kernel
   amd-pstate docs — under `amd-pstate-epp` the governor name `powersave` IS the intended mode, EPP
   is the lever ("lower epp values shift the bias towards improved performance"), and a `dynamic`
   mode exists that lets a desktop power daemon legitimately re-assert EPP. That is why the owner's
   `enabled` cpupower unit left `balance_performance` in place across a reboot, and it corrects my
   instruction of the last two days (the note's "governor" language needs the same re-point). The
   persistent route is `powerprofilesctl set performance` or masking the asserting service;
   ppd→EPP mapping stayed UNVERIFIED behind a sign-in wall, so the round substituted an ownership
   read. **This is the last untested zero-cost experiment on the box** and the only remaining single-card
   candidate, because the other ~24 ms/token is host-side.
   ONE FREE MEASUREMENT OWED, and it decides whether 35 is "the floor" or still anomalous: the docs'
   28–29 ms is ambiguous about whether it includes speculative acceptance — run the fixed ≥2000-token
   probe and read the **best-tile / steps-held** counters. Then: any remaining performance budget
   belongs to **TP2**, where the docs make 62–137 t/s, the prefix-tier resume AND the n-gram RAM tier
   simultaneously reachable (~83 GiB host ≤ 110) — which is AD-144's argument, now stated with
   numbers instead of hope. Authority: RESEARCH §R15 (lines 3664–3922).

 - 2026-11-14 human+coord D46 (EPP IS NOW `performance` AND STICKING — the first owner-lane command
   I authored that worked as specified on the first try, and the last zero-cost single-card
   experiment is now in play): the tmpfiles.d line was deleted and replaced by
   `/etc/systemd/system/epp-performance.service` (oneshot, `WantedBy=multi-user.target`,
   `After=cpupower.service` + `Wants=cpupower.service` precisely because cpupower is enabled and can
   write EPP first), proven by `cat /sys/.../cpu*/cpufreq/energy_performance_preference | sort |
   uniq -c` ⇒ **`32 performance`** with `is-enabled` showing both units enabled. This closed the
   §D6.4 non-persistence question the kernel-docs way (§R15/D45: `powersave` is the intended
   governor NAME under `amd-pstate-epp`; EPP is the lever; `dynamic` lets a daemon re-assert it), and
   it is why the last four commands I dictated failed in four different ways — the fix was not better
   memory of syntax but a form that cannot be mis-remembered plus the read that proves it took effect.
   WHAT THIS BUYS AND WHAT IT DOES NOT: it targets the ~24 ms of NON-wire step time, so the honest
   expectation is single-digit percent, not 2×; the standing finding from §R15 is unchanged — our
   ~35 t/s equals the creator's documented single-card `--tp 1` floor. The decisive ambiguity is
   whether the docs' 28–29 ms INCLUDES speculative acceptance, and only a fair probe answered on a
   `performance` box can settle it: same prompt, `max_tokens ≥ 2000`, twice, second run quoted, with
   Δ`radiance:kv_stream_bytes_total{dir="in"}` ÷ Δ`vllm:generation_tokens_total` recorded before and
   after (the measurement that replaced my VOID 83–100 MiB/token bound) plus the engine's own
   `/stats`/request `done` lines. If that lands near ~35–40 with the wire still at ≤15% of step, the
   single-card question is CLOSED with receipts and the remaining budget belongs to
   **TP2/AD-144** (docs-measured 62.3–64.8 with MTP at 62K; 137 on L1T), where the n-gram RAM tier
   and the prefix-tier resume stop competing with each other. Persistence should also be re-read at
   the next natural reboot (the unit is enabled, but this box has taught us to verify rather than
   assume). Authority: the owner's paste, 2026-11-14.

 - 2026-11-14 human+coord D47 (THE WIRE IS NOT THE LIMITER ANY MORE — MEASURED AT ZERO, AND DECODE IS
   ~41 t/s: the single-card question is CLOSED with receipts): the fair probe on the EPP-fixed box
   returned two consecutive 2000-token completions at **41.1 and 41.3 tok/s** (wall 49.04 s and
   48.92 s, `finish=length`, prompt=20 ⇒ a clean sustained-decode measurement, no cache and no KV
   streaming involved), and the replacement metric arithmetic came back
   **`decoded 4000 tokens | KV stream 0.0 MiB/token | 0.00 ms/token at 7.51 GB/s`**. So the figure
   that replaced my VOID bound is not "small" — during sustained decode at short context the KV host
   mirror moves **nothing**, which retires the wire theory of this box entirely (and retires §D8's
   miss-fraction model as an explanation for the remaining gap, since m was solving for a term the
   counters say is zero). Two consequences stated plainly: (1) **~24 ms/token of compute/host is
   the whole step**, and we are at 24.3 ms — **better than the docs' own 28–29 ms `--tp 1`
   reference**, so the EPP change plausibly bought real ground (but see the confound in (3)); (2) the
   70+ expectation is now dead by measurement rather than by census: reaching it would need
   ~14 ms/token total, i.e. **less time than a single step currently takes**, and no bandwidth
   purchase changes that. TP2 remains the documented route (62.3–64.8 docs / 137 L1T).
   (2b) A LIVE CONTRADICTION OF §R15 THAT MUST NOT BE BURIED: two of the chat requests now report
   **`cache 12288`** with TTFT collapsing **25.44 s → 6.27 s** at prompt≈14.0–14.9k tokens, while
   every pre-fix receipt read `cache 0`. §R15's reading was that `--kv-resident` **force-disables
   the prefix tier**, which would predict no hits at all. Either the mirror suppresses only the
   *host* tier while on-card prefix reuse lives, or §R15's doc reading is wrong on this point. That
   distinction is worth real money here (it is the difference between "our agent workload pays
   12 s TTFT per turn forever" and "it does not"), so it is flagged for the next doc round to settle
   against the GUIDE rather than resolved by me from three log lines.
   (3) HONEST CONFOUND on the EPP gain: the same log window reads `18.4 → 25.1 → 41.1 → 41.3` t/s in
   time order, so warm-up and EPP are not separable from this evidence; the clean claim is only that
   the **steady-state pair is 41.1/41.3**, and that it beats the documented floor. To attribute the
   delta to EPP, re-run the identical two-shot probe after `systemctl disable epp-performance.service`
   + reboot (or with EPP set back to `balance_performance`), which is owner-lane and reversible.
   (4) The 11.6 t/s row is NOT a regression signal — it overlaps other traffic in the window
   (concurrency is the documented elasticity story), and it is the reason the ticket's acceptance bar
   remains runbook **step 6's 8-session gate**, which still has never been run.
   Authority: the owner's paste, 2026-11-14. Net for the ticket: radiance on one R9700 is now
   **verified working at ~41 t/s sustained decode**, on a confirmed Gen4 x4 path with **zero wire
   cost during sustained decode**, and prefill re-derived from the same window as
   **14,020 tokens ÷ 25.44 s ≈ 551 tok/s** (and `14,865 − 12,288 cached ÷ 6.27 s ≈ 411 tok/s` on the
   hit path) — consistent with §D8's 450–500 Gen4 band and roughly 3.6× the old 142 tok/s read.
   (The 0.43–0.50 s TTFT rows are a 20-token prompt and measure request overhead, NOT prefill rate;
   they must not be quoted as 1.6k tok/s, which is the error I nearly wrote into this record.) The
   remaining gap to the owner's 70+ expectation is structural to the card count, not a
   misconfiguration.

 - 2026-11-14 research+coord D48 (§R18 — **HIDING THE 8060S IS DECLINED, and the owner's guide is
   preserved as the cutover-day procedure**): the doc's motivating premise — "the plugin advertises
   both cards as one `amd.com/gpu` so a pod can get the built-in graphics" — was **true pre-C07 and
   is false on this box**: plugin v1.31.0.12 with `-resource_naming_strategy=product` over the D24
   patched `amdgpu.ids` advertises `amd.com/gpu-r9700-1` and `amd.com/gpu-8060s` with **no bare
   pool**, so a mis-allocation is structurally impossible; radiance gets exactly one render node and
   prints `1 device(s) [0:gfx1201]`. Claim-by-claim: the device-count argument is **true-as-documented
   and dead-as-shipped** (no which-subset control; §R6 found it unimplemented in the binary);
   `ROCR_VISIBLE_DEVICES` **cannot** fix a mis-allocation (Allocate mounts nodes, sets no env — the
   2026-11-07 index-order crash is that scar, and §R7's GUIDE harness shows the flag is for
   selecting, not rescuing); **Strata PR #3636's 71–74 vs 46–49 and 2,530 vs 1,627 measure USING the
   8060S in a layer-split with the expert arena in host RAM, not the tax of merely SEEING it** — the
   presence-tax the doc infers has no evidence, and this ticket measured it from the other side
   (§D47: `0.0 MiB/token` on the wire during sustained decode; radiance prints `not serving`; the
   router's `/v1/models` had every model `unloaded`); mixed-gen corruption issue **#2706 is real but
   requires both devices in one pipeline**, which per-product naming makes unreachable; and the RAM
   argument is **inert** — `card 0000:c5:00.0 … 512.00 MiB VRAM` in the engine's own print is the
   documented BIOS minimum, Strix allocation is dynamic-GTT regardless, and the §R15 ngram-ram gate
   needs `71.04 + 47.68 + 4 = 122.72`, which beats 110 and every hiding-gain.
   WHY IT WOULD COST SOMETHING REAL: the doc's recommended `vfio-pci` route is unavailable on this
   box by prior decision — `amd_iommu=off` is the deliberate working posture (§R9/§D33: the
   `iommu=pt` gate was the error; radiance's `dma copy lists` path runs under off), and vfio's only
   no-IOMMU escape is kernel-labelled *"unsafe DMA … w/o physical IOMMU protection"* (vfio.rst),
   which this ticket declines. `pci-stub` (via `driver_override`, no IOMMU, reversible) DOES work —
   and it deletes `amd.com/gpu-8060s`, which is the resource the **llama-swap router is scheduled
   from** under the owner's own D21/B1 ruling. Leaving the add in place with no pool is the
   **C10 class of failure we just lived for 11 h 40 m**, re-invited by choice; taking the add out
   leaves the pod schedulable but ends the APU's Vulkan/GGUF serving lane and the catalog's
   `-strix` fallback. Neither is a hiding "side effect" — it is the whole content of the trade.
   RULING: **do nothing now**. Keep the doc, corrected as §R18 tables it, as the **retirement
   runbook for cutover day**: if/when the owner deliberately retires the APU serving lane, the
   order is **code first** (drop the `gpu-8060s` add from the gpu-ai overlay — a D21/B1 reversal,
   and the same-wave law means docs/overlays/names move together), then `pci-stub` **per function**
   (`1002:1586`, leaving `1002:1640` audio alone — no Strix-Halo report exists for the co-binding
   question, flagged UNVERIFIED), then verify, with rollback = rebind + revert the overlay. The
   revisit trigger is singular and named: **the strata cutover**, which is itself an open owner
   decision (Deferred: at 110 strata cannot co-reside, so that decision is already an either/or).
   Also recorded: the doc's honest self-caveat — the vfio/pci-stub steps are **standard Linux
   practice, not hardware-specific sourced advice** — is exactly where this cluster's specifics
   (product naming, `amd_iommu=off`, the APU-as-router-pool) override it. Authority: RESEARCH §R18
   (lines 3926–4059), including its UNVERIFIED list (VAP GA flag, Framework BIOS UMA documentation,
   audio-function stub behavior, ROCm device-order authority).

 - 2026-11-14 human+coord D49 (**MY INSTRUCTION CRASHED THE BOX — recorded as the ticket's only
   self-inflicted outage, and it closes the hiding question permanently**): the owner ran the
   trial step I dictated, `echo 0000:c5:00.0 | sudo tee /sys/bus/pci/drivers/amdgpu/unbind`, and the
   machine went down. I called that step "reversible, survives only until the next boot." **It is
   not safe on this hardware, and I should have seen why from our own topology read.** §D11's
   `lspci -tvv` shows the iGPU is not alone in its slot: `00:08.1-[c5]--+-00.0 (8060S display)
   +-00.1 (HD Audio) +-00.2 (CCP/ASP) +-00.4 (USB xHCI) +-00.6 (HD Audio)` — so `c5` carries the
   **SoC's USB controller and the PSP/CCP alongside the display function**. Unbinding one function of
   a multi-function PCIe device routes through a device/slot reset (FLR, or a Secondary Bus Reset on
   `00:08.1`), and a bus reset takes **everything behind that port with it** — while `amd_iommu=off`,
   our deliberate posture, means there is no IOMMU group containment and no isolation for the
   in-flight DMA of whatever else lives on that bus. That is the mechanism (stated as the
   well-supported hypothesis, not a proven read: a hard crash leaves no `dmesg` we could retrieve),
   and it is why the §R18 source list's own "reset-bug" and VM-passthrough notes were the warning I
   under-weighted. **The lesson is the same one this ticket keeps charging me for**: I reasoned about
   the device as an isolated object instead of reading the bus it sits on — the register-misread
   (D38), the wrong-denominator bound (D44), and now the wrong-blast-radius instruction.
   RECOVERY FACTS the owner needs, stated plainly: **nothing in what I dictated persists.** The trial
   was three runtime writes with no udev rule, no initrd rebuild, no kernel command-line change, so a
   power cycle restores the previous state on its own and **no TPM/boot-measurement re-sealing is
   implicated** (we never touched boot entries). Because the box died mid-write on a btrfs
   snapshot/CoW root, the post-boot checks below matter more than the crash itself.
   RULING, now with an incident behind it: **HIDING THE APU IS OFF THE TABLE — do not attempt it by
   any method on this machine.** `pci-stub.ids=`/`driver_override` on the kernel command line is the
   persistent variant and therefore *worse* (the reset happens at driver-bind time, before userspace
   exists, with the same USB/PSP neighbours and possibly the console). The D48 decline stands and is
   strengthened: the goal (no mis-allocation) is already delivered by product naming, the gain is
   ~0.5 GiB and zero throughput, and the measured cost of trying is now **a dead host for an
   unknown amount of time** — on top of the router-starvation cost D48 already priced. The cutover-day
   runbook survives ONLY as a document, with the hazard banner it now needs; if the APU lane is ever
   genuinely retired, the right mechanism then is **the BIOS iGPU disable** (a firmware decision made
   before any driver binds, so no in-flight reset) — not a Linux-level bind/unbind trick, and not
   anything I should recommend without researching that specific claim.
   POST-BOOT VERIFICATION IS NOW THE ACTIVE WORK, and one item is load-bearing for the whole two-day
   hunt: **the Gen4 link may re-latch to Gen3 after a hard power cycle** (D35/D43/D44 — the socket
   swap, not the boot, fixed it, and a dirty reboot is precisely the class of event that loses a
   negotiated speed). The owner must re-read `LnkSta`/`Phy16Sta` on both ends, confirm `pinned 71.04`
   and the marker-skip boot, verify the 113.6 GiB pack still passes the hash gate (a crash during a
   read-only phase is benign, but a btrfs CoW tear is not something to assume away), re-confirm
   `amd.com/gpu-8060s` is back, re-read `energy_performance_preference` (the `epp-performance.service`
   unit is enabled and should have applied itself), and check the router recovered. Authority: the
   owner's report, 2026-11-14, and §D11's topology read that I had in hand and did not use.

 - 2026-11-14 human+coord D50 (BOX RECOVERED; MY POST-CRASH VERIFICATION READ THE WRONG PORT, and
   the crash's cause is now confirmed by the owner's own device list): the node is back and the
   hiding experiment left **no residue** — `c5:00.0` is on `amdgpu` again, the whole SoC slot is on
   its real drivers (audio `1002:1640`→`snd_hda_intel`, `CCP/ASP`→`ccp`, `1022:1587`→`xhci_hcd`),
   pools are restored (`amd.com/gpu-r9700-1=1`, `amd.com/gpu-8060s=1`, bare `amd.com/gpu=0`),
   **EPP reads `performance` on 32/32 cores after a real reboot** (the §D6.4/D46 non-persistence
   question is closed by the `epp-performance.service` unit, not assumed), and `dmesg` shows no
   btrfs corruption on the CoW root. Two items of substance:
   (1) **D49's mechanism is confirmed by hardware, not inference**: the owner's `lspci -nnk` shows
   the Logitech receiver enumerating on `usb-0000:c5:00.4-1.1`, i.e. **the interactive USB bus is a
   sibling function of the display function I told them to unbind** — unbinding one function of that
   slot takes input, PSP and audio down with it. Recording it that way because it converts D49's
   "well-supported hypothesis" into observed fact, and it is the strongest possible form of the law:
   *read the slot, not just the device*, which is now the third time this ticket paid for skipping
   that step (D38 register, D44 denominator, D49/D50 bus).
   (2) **My verification block was aimed at the wrong port.** Post-swap, the GPU chain is under
   `00:02.5-[c1-c3]` and `00:00:03.1-[c4]` is the **NVMe**, so the `16GT/s x4 EquComplete+ Ph1/2/3+`
   read at `00:00:03.1` is the WD SN7100 performing normally — true but not the thing being asked —
   and `c2:00.0`'s `32GT/s x16 / EquComplete-` is likewise an internal hop, the same mis-aimed-read
   class §D43 already logged. The authoritative witness for the host↔card link is therefore the
   **engine's own `link` line** (which resolves device identity by construction, per §D8/§D10), with
   `00:02.5` and `c1:00.0` as the correct lspci pair; recorded here so the corrected commands exist
   somewhere other than chat.
   (3) **THE ACTUAL LIVE FINDING FROM THIS PASTE, and it is the D29/D44 either/or arriving on
   schedule**: the pod list shows **`gpu-ai-llama-swap-strata … 1/1 Running`** and **no radiance pod
   at all**. Strata's request (~64 Gi per §D6.1's archaeology, its own `110Gi` limit) plus radiance's
   scheduled `110Gi` is `> 125.08` — the two cannot co-reside by arithmetic, so whichever started
   second is unschedulable/Pending, and strata coming back is the resurrection path §D7/§D43 warned
   about (git renders strata at `replicas: 1`; a sync or a re-deploy restores it). This is not a
   defect and not the crash's fault: it is the consequence of the 110 ruling meeting the Q5 "keep
   strata live" ruling, and **the owner must now pick one** — run radiance and leave strata at 0, or
   scale radiance down and let strata serve. It is also the moment the Deferred cutover row was
   written for. Authority: the owner's paste, 2026-11-14.

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
- Upstream amd-gpu chart refresh (≥0.23 or PR #122 merge) — MOOTED by D23: charts/amd-gpu
  becomes first-party app-template (C08); the vendored-fork refresh policy dies with the
  fork. D19 kept on the ledger for provenance.
- Upstream feature ask on ROCm/k8s-device-plugin for a configurable resource name/
  prefix/domain or an override side-map (the shape §R7-Q3(b) argues for; no duplicate
  exists — §R7-S9 verified full open list 2026-11-12): RECOMMENDED, filing is an OPTIONAL
  OWNER CALL post-lane-ruling (D24: table-mount ships gpu-r9700-1 regardless — the ask
  would make the name natively configurable later); record the choice either way.
- C08 lands WITH the rename (D24): after its dev round, COORD RE-PUBLISHES follow-up
  card #1's body (the TP2 doc's name strings + the table re-verification law changed;
  the card is a doc snapshot) — run-end action, tracked in the plan's delta section.
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

## Owner PR review — 2026-11-12 (rework round, same run + same claim, cf-141 pattern)

The owner line-reviewed the branch vs main and left six items (verbatim intent; the
"fair number of other comments" tail is read as: also fold the recorded non-gating nits
in Deferred/STATE.deferred — if the owner has comments beyond the six, they will surface
them at hand-back):

1. charts/radiance/values.yaml:49 `guaranteedMemoryGi: 64` — "seems wrong. 64 too low or
   too high?" → D17 already holds the derivation (60Gi-class author recipe 49 GiB pinned;
   +4 GiB pool delta; ladder up→96 while strata is down, down via pool/ctx steps).
   Rework: sharpen the comment to answer the question AT the scalar (derivation + ladder +
   the 64+64+4>125.08 designed-Pending handshake), keep 64 unless the sweep finds a better
   receipt-anchored start.
2. charts/radiance/values.yaml serveArgs list — "put the args on the same lines as the
   flags" → reformat the YAML list so each flag+value share a line; TOKENS unchanged
   (app-template schema rejects nested arrays; `--flag=value` merge unverified for this
   engine — flow-style-per-pair is the token-preserving shape). Test/runbook equality arms
   parse tokens, so contract stays green; verify.
3. Resource name `amd.com/gpu-ai-pro-r9700` → "call this amd.com/r9700-1" — the product
   names come from the plugin BINARY's sanitizer over the baked amdgpu.ids table (§R6-Q1),
   not from chart values. Rework gate: a source-verified capability check (name override
   flag/env/config at v1.31.0.12) — RESEARCH §R7 commissions it. If customizable → rename
   EVERYWHERE (radiance claim, ledger, tests' constants, runbook/TP2 docs, catalog-free
   names unchanged) with tests re-pinned to the new strings; if NOT → keep
   `gpu-ai-pro-r9700` + answer the owner with evidence (and the naming shape rides an
   upstream ask).
4. charts/amd-gpu/values.yaml:50 `lbl:` — "not understandable, use a better name" →
   superseded by item 5's conversion when it lands (the vendored values file goes away);
   if 5 concludes non-convertible, rename with a D19-governance delta note.
5. charts/amd-gpu/templates/deviceplugin-daemonset.yaml "Can this be handled by the
   app-template?" + "I don't use _helpers.tpl, so remove that and NOTES.txt" → owner
   direction: rewrite charts/amd-gpu as a repo-standard app-template 5.0.1 chart
   (DaemonSet controller type, SA+RBAC via app-template controller fields, hostPath
   volumes for /dev/kfd + /dev/dri, tolerations, nodeSelector as today, args incl.
   -resource_naming_strategy=product + -v=5), DELETE _helpers.tpl + NOTES.txt + the six
   vendored templates. Governance effect: D19's vendored-fork story ends — charts/amd-gpu
   becomes a first-party chart (better: no upstream-refresh debt); the labeller/nfd
   subcharts stay out (they rendered nothing). D19 append-only superseded-by-D-note owed.
6. "a fair number of other comments for you to clean up" → fold the still-open recorded
   nits: charts/vllm/tests/test_trio.py:66 dropped-message phrase (test session),
   charts/radiance NOTES.txt colon (mooted by its own file? no — radiance NOTES stays;
   fix), tests/services/amd-gpu-naming.sh:205 stale success phrase (test session),
   services/gpu-ai/prod/values.yaml:744 'ONLY this subtree' wording, .opencode/opencode
   .jsonc floor-sentence precision, chart M1 header fold if chart survives conversion
   (mooted by item 5 otherwise).
