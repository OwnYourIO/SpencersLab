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
  though `ttm.page_pool_size=29360128 ttm.pages_limit=293610128
  amdgpu.lockup_timeout=30000` + `amd_iommu=off` are visibly custom-set in the paste —
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
