# RESEARCH — AMD GPU device-selection determinism (radiance multi-instance)

`agent-research`, 2026-11-22. STORM method (5 grounded perspectives, per-ask interviews,
contradiction map, peer pass). Storm run dir:
`/tmp/opencode/storm-radiance/storm-runs/amd-gpu-device-selection-determinism-in-kubernetes-rocm-k8s/`
(interviews `raw/`, numbered `sources.md` — the [n] citations below, `contradictions.md`,
`report.md`). Citations resolve to the Sources table at the bottom; code citations are
pinned to tags/branches read at those refs, not `HEAD`.

Answers EXPLORE.md §8 "Needs research (a)/(c)" and the coordinator's six asks. EXPLORE.md
and cf-143 RESEARCH.md §R6/§R7 were treated as claims to re-verify, not trusted input;
every cf-143 fact this round touched **survived re-verification at pinned tags** (see
Contradiction map, C7).

**Ground truth this research stands on** (verified locally/EXPLORE before research): image
`docker.io/rocm/k8s-device-plugin:1.31.0.12` pinned in `charts/amd-gpu/values.yaml` with
args `-resource_naming_strategy=product`; the patched minimal `amdgpu.ids` ConfigMap (R9700
row `7551, C0, r9700-1` + nine 1586 APU rows); live capacity `amd.com/gpu-r9700-1: 2`,
`amd.com/gpu-8060s: 1`, bare `amd.com/gpu: 0`; KFD ordinals 0/1 = the R9700s (BDF c3/c7),
2 = the APU. Plugin latest release is still v1.31.0.12 (2026-11-06) [7]; DRA driver latest
release is still v1.0.1 (2026-07-22) [22].

---

## R-Q1 — Does the pinned device plugin expose a visible-devices strategy, and what env does it inject?

**VERDICT: No strategy exists and no env is ever injected. "Which card" is pool-name +
claim-count; when a genuine choice remains, the plugin's best-effort allocator is
deterministic in practice (single-card claims take the lowest KFD NodeId card), but the
API contract labels this advisory, and per-lane pinning to a *specific* card among two
identical cards is structurally impossible in the plugin path.**

- The pinned plugin binary has **exactly two flags**: `-pulse` and
  `-resource_naming_strategy {single,mixed,product}` (default `single`). There is no
  device filter, no device-id strategy, no CDI surface — unlike NVIDIA's plugin
  (`DEVICE_ID_STRATEGY=uuid|index`, `DEVICE_LIST_STRATEGY`), which is why people expect
  one [1]. The device-plugin API itself has no "visible devices" concept at all [9].
- `Allocate` injects **device files only** — `/dev/kfd` plus `cardN`/`renderDN` per
  allocated ID — and the file contains **zero `Env` occurrences** [4]. A plugin-scheduled
  pod therefore *cannot* receive `ROCR_VISIBLE_DEVICES` from the plugin; the injected
  device set is the isolation, and inside the pod the runtime sees exactly the claimed
  cards, renumbered from 0. This is the mechanism-level reason the radiance suite bars
  visibility env (`charts/radiance/tests/radiance_testlib.py` `ABSENT_ENV`) and why that
  bar costs nothing.
- Which card a claim gets, per kubelet release-1.36 source [8]: accounting is per
  resource name; `available = healthy − allocated`; the kubelet calls the plugin's
  `GetPreferredAllocation` only when a genuine choice remains and consumes
  `preferred ∩ available` first. The kubelet passes `available` **unsorted**, so all
  observed determinism lives in the plugin re-sorting.
- The AMD plugin reports `GetPreferredAllocationAvailable: true` and its
  `BestEffortPolicy` scores subsets by topology (XGMI < PCIe, same-NUMA, partition
  locality) [4][5][6]. Two decisive facts: when `size == len(available)` it returns
  everything (a `--tp 2` claim trivially gets both cards [5]); for size 1 it enumerates
  candidate subsets over `available` **sorted by KFD NodeId ascending**, all single-device
  subsets weigh 0, and the first minimum wins ⇒ **a free single-card claim deterministically
  lands on the lowest-NodeId card in the pool** [5][6]. Ties cannot otherwise occur for
  size-1 claims.
- Honesty caveat: `GetPreferredAllocation` is documented as advisory — "not guaranteed to
  be the allocation ultimately performed" [9], and open upstream PRs #214 (enumerate
  candidate subsets as combinations) and #213 (unscored interconnect = worst case) show
  the allocator is still being sharpened. The determinism above is *observed-from-source
  behavior of the pinned tag*, not an API guarantee. The plan's acceptance criteria must
  phrase it as such.
- Consequence for the four-lane roster: single-card lanes land deterministically (lowest
  NodeId among the cards *not yet allocated* — so the first-scheduled lane takes that card
  and a concurrent second single-card claim takes the other); TP2 lanes get both cards;
  in-pod rank0 on a TP2 lane is the engine's enumeration of the injected pair, which
  nothing user-settable controls and correctness does not depend on [4][37].

## R-Q2 — What forms does `ROCR_VISIBLE_DEVICES` accept (indices, UUIDs, bus IDs)?

**VERDICT: comma-separated tokens, each either a KFD integer index or a UUID token that
prefix-matches `GPU-<16 uppercase hex>` (the 64-bit KFD UniqueID — NOT NVIDIA's dashed
form). Accepted at least since ROCm 6.3. No bus-ID form. Failure semantics are silent and
hostile (a bad token truncates the visible set). HIP/CUDA_VISIBLE_DEVICES are index-only.**

- `RvdFilter` (read at master, rocm-rel-6.4.1.2 and rocm-rel-6.3 — identical in kind)
  splits on commas, uppercases, and matches each token against every device [11][14][15]:
  - **UUID tokens** compare against the device's rendered UUID `GPU-%016X` of the 64-bit
    UniqueID; matching is **prefix**, token length 5–20; an ambiguous prefix fails that
    token. UniqueID 0 renders `Invalid-UUID` and can never be matched.
  - **Integer tokens** parse via `strtol` base 0 (hex/octal accepted) as indices into the
    KFD discrete-GPU list.
  - There is **no PCI bus-ID form**.
- Error semantics: any bad, duplicate, or out-of-range token **silently truncates the
  accepted list** — `ROCR_VISIBLE_DEVICES=0,7` on a 2-GPU box yields exactly one visible
  GPU with no error anywhere; an empty-but-set variable yields zero visible devices; the
  user's token order becomes the new visible-ordinal order [11]. Applied at topology
  build (`BuildTopology`) [13], before HIP enumerates — so HIP ordinals renumber from 0
  inside the filtered set.
- Docs agree on capability, not format: HIP docs say ROCR accepts "indices or UUIDs" and
  recommend it on Linux, while `HIP_VISIBLE_DEVICES`/`CUDA_VISIBLE_DEVICES` are
  index-only [16][18] — but the docs' dashed-UUID **example cannot match the code's
  format** (contradiction C2); the code is authority [11].
- Independent witness: ollama's fix commit states "only ROCR_VISIBLE_DEVICES supports UUID
  based identification", moved to preferring Uuid, and records that ROCm numeric indices
  ≠ sysfs card numbering while remaining order-consistent [19].
- Where a UUID comes from: KFD exposes `unique_id` per node in
  `/sys/class/kfd/kfd/topology/nodes/*/properties` (kernel renders `adev->unique_id`)
  [20][21]. Whether consumer RDNA (gfx1201) fuses a **nonzero** unique_id is
  board-dependent and **unverifiable from source** — one live check (OQ-R1) gates any
  UUID-based pin. Until then the repo's index-based pins (vllm/strata lanes) are the only
  proven-stable form.
- Plan note: the lab's vLLM-lane idiom `ROCR_VISIBLE_DEVICES=<absolute> +
  HIP_VISIBLE_DEVICES=0` [charts/vllm/values.yaml] is exactly the canonical two-step the
  source implies: ROCR selects the physical card, HIP renormalizes so the engine sees
  device 0 [11][16][38].

## R-Q3 — Does the ROCm DRA driver fit as a replacement for named pools?

**VERDICT: not today — watch-list. The 1.36 platform side is ready (DRAExtendedResource
Beta, on by default), the closest-hardware field report is encouraging, but the shipped
driver (v1.0.1) lacks the classic-request bridge, its claim names are unstable, `productName`
is empty on R9700, and an open reboot/CDI bug makes running-claim restore unsafe. If ever
adopted, CEL-select on `pciBusID` only.**

- Platform side (k3s is 1.36): `DRAExtendedResource` is **Beta and on-by-default in 1.36**
  — a DeviceClass carrying `extendedResourceName: amd.com/gpu` lets classic pod requests
  of that extended-resource name be served by DRA claims with CEL device selection
  [31][32][33][34]. Also on in 1.36: DRAPartitionableDevices (Beta), DRAPrioritizedList
  (GA), DRAConsumableCapacity (Beta), DRAListTypeAttributes (Alpha) [31].
- Driver side: `extendedResourceName` and the SPX AutoPartition DeviceClass exist **only
  on the develop branch** — absent at the shipped v1.0.1 tag (latest release, 2026-07-22)
  [22][24]. Issue #131 asks for a release carrying it [29]; #136 shows source-install
  still ships a v0.1.0 image (appVersion bug) [30]. Doc-vs-shipped gap: C5.
- Stability: claim canonical name is `gpu-<cardN>-<renderDN>` — DRM-minor based, **changes
  across reboots/reprobe** (upstream issue #83) [23]. The struct carries a UUID attribute
  that is **never published** [23]. Published attributes: `deviceID`, `pciBusID`,
  `pcieRoot`, `numaNode`, `productName`.
- Field evidence on the identical card (issue #135: k3s v1.36.6 + 2× R9700): v1.0.1
  discovers both cards; a CEL pin on `resource.kubernetes.io/pciBusID` works; TP=2 via two
  claims works; shared claims work; a restricted pod received `/dev/kfd` + one renderD via
  CDI; **`productName` published EMPTY on R9700** (CEL must not select on it); `numaNode`
  was −1; names `gpu-0-129`/`gpu-1-128` unstable [28].
- Reliability blocker: **#75 "reboot breaks CDI" is still open (2026-11-11)**; the fix PR
  #78 is open unmerged [25][26]; #86 open [27]. For a single-node homelab a reboot
  invalidating device access of running claims is exactly the failure mode the lab cannot
  GitOps around.
- Fit conclusion: adopting DRA now would trade the incumbent's one proven weakness
  (no specific-card pin among identical cards — which DRA *would* solve via pciBusID CEL
  [28]) for three live ones (unreleased bridge, unstable names, open reboot bug). The
  multi-instance ticket's acceptance criteria are already satisfiable on the plugin path
  (R-Q1); DRA stays a recorded revisit with explicit triggers (OQ-R4).

## R-Q4 — Deterministic multi-GPU AMD serving patterns (pattern map)

**VERDICT: five distinct patterns exist; for this repo's roster, pool arithmetic (P1/P2)
is sufficient and complete — it gives deterministic card landing for every single-card
lane and trivially-correct TP2. Per-lane *specific-card* pinning among two identical
cards is achievable only outside the plugin path (P3 hostPath+ROCR, or future DRA P6).**

- **P1 — pool arithmetic, plugin lane (the radiance lanes).** One claim per pod against a
  per-name pool; membership final, count integer, requests==limits [10]. Determinism:
  lowest-available KFD NodeId wins single-card claims; concurrent claims take distinct
  cards by occupancy [5][8]. This is the lab's existing, live-proven idiom and the basis
  for the four-lane roster: both R9700s under one derived name (`gpu-r9700`, count 2) feed
  flash-TP2 (both cards), flash-TP1 (lowest free card), and replicas-0 reserve lanes
  (claim shape validated by scale-up).
- **P2 — TP2 claim.** `count == pool size` ⇒ the allocator returns all devices; nothing to
  pin [5]. In-pod rank0 is the engine's enumeration of the injected pair — the radiance
  engine prefers discrete devices and restricts to the first discrete card's arch, and
  states plainly that ROCR/HIP env control what the runtime exposes [37]; correctness is
  rank-order-independent.
- **P3 — hostPath + ROCR/HIP two-step (the llama-swap/vllm lanes).** privileged/hostPath
  lane chooses cards inside via `ROCR_VISIBLE_DEVICES` (indices today, optionally UUIDs
  post-OQ-R1) + `HIP_VISIBLE_DEVICES=0` renormalization [11][16][38]. Hardware-stable
  choice *is* possible here in a way the plugin path cannot match — that asymmetry is the
  honest boundary of "deterministic assignment".
- **P4 — engine-internal selection.** radiance's `RADIANCE_GPU` names a card within the
  visible set [35][36]; under plugin injection the pod sees only claimed cards, so P4 is
  redundant for radiance lanes and must not be added (suite bars the env; engine flags
  would be dead config).
- **P5 — UUID pinning.** Supported since ≥6.3 [14][15], battle-tested by ollama [19];
  blocked on the nonzero-`unique_id` live check for consumer RDNA (OQ-R1). Silent
  truncation [11] means a wrong UUID fails *closed* (engine sees zero GPUs → crash-loop,
  visible) rather than mislanding — an acceptable failure mode.
- **P6 — DRA claim with pciBusID CEL.** Proven on this exact card by #135 [28]; gated by
  R-Q3's blockers. External 2×R9700 deployments (level1techs guide, paquin's R9700
  Radiance-vLLM rig) converge on the same shape: one engine per card or one TP2 engine —
  per-release roster, not per-pod steering [39][40].

## R-Q5 — Rename blast radius: `gpu-r9700-1` → `gpu-r9700`

**VERDICT: one atomic GitOps wave or not at all. The name table is read once at plugin
startup; the rename flips old capacity to zero permanently while running pods keep their
injected devices; every pod spec still carrying the old name PENDINGs forever and survives
kubelet restarts. EXPLORE §2b's ordering law is confirmed from source; the wave's content
is: patched ConfigMap row + plugin rollout + every consumer request name + both guard-test
sweeps' needles (EXPLORE §2c/§2d) — plus the stale "each pool holds one device" comment fix
(C1).**

- Mechanics chain: `naming.LoadProductIndex(naming.IDsPath)` runs **once at startup**
  (fatal if the file is missing) [1][3]; the derived name set is what the single
  ListAndWatch stream advertises [4]. Editing the ConfigMap row (`r9700-1` → `r9700`) and
  rolling the plugin means the kubelet simultaneously starts advertising `amd.com/gpu-r9700`
  and stops advertising `amd.com/gpu-r9700-1` — there is no interval where a plugin
  advertises both from one table, and the name itself exists nowhere but the table.
- Old-name consequences [8]: kubelet `GetCapacity` for a name the plugin no longer
  advertises goes to zero and **stays** zero (re-registration would be the only fix and
  never comes); already-allocated pods keep running — their devices are injected and
  checkpointed — but any *new* pod (including a scale-up of a replicas-0 lane, and any
  pod rescheduled after a node reboot) requesting the vanished name is unschedulable:
  extended resources are integer, non-overcommittable, request==limit, and such a pod
  "remains in the PENDING state as long as the resource request cannot be satisfied" [10].
- Failure is loud and attributable: `FailedScheduling … Insufficient amd.com/gpu-r9700-1`
  — recognizable, and the revert is the same wave rolled back (ArgoCD).
- Therefore the rename cannot be staged (config half first, or plugin first): whichever
  order, one class of pods is orphaned against a dead name between halves, and the window
  is not bounded by ArgoCD sync timing but by whenever the plugin pod actually rolls.
  EXPLORE §2b ("one-wave sweep") holds, with this source-level mechanism behind it.
- Local law interaction: the amd-gpu chart's hot-reload rule (ConfigMap edit reloads the
  plugin) is what makes the wave self-applying; the rename is *not* a chart-version or
  image change — no version bump (repo hard rule), the ConfigMap edit is the trigger.
- Replicas-0 lanes (27b TP1) carry no running pod, so the wave has zero runtime risk for
  them; their danger window is future scale-up against a stale values name — same wave,
  same fix.

## R-Q6 — Can the same physical card be exposed under two pool names?

**VERDICT: No — impossible through the pinned plugin, and any out-of-band way to do it is
a guaranteed double-booking. Rejected; if the goal is "lane A prefers card1, lane B card2",
that is P3/P6 territory (R-Q4), not naming.**

- Inside the plugin: `bucketDevices` places **exactly one device into exactly one bucket**,
  and under `product` strategy a device's bucket — hence its resource name — is derived
  from its table row alone [3][4]. Two identical R9700 rows derive the *same* name (which
  is precisely why the lab patched the row text today); there is no per-card override,
  filter, or multi-advertise flag in the binary's two flags [1]. One card under two names
  cannot be produced.
- Outside the plugin (second DaemonSet / stub advertising the same card under a second
  name): kubelet and scheduler account extended resources **strictly per name** — the
  two names are independent inventories with no physical-card relation [8][9]. "Devices
  cannot be shared between containers" is enforced per name only [9]. Two pods, one per
  name, land on the same physical R9700 with zero admission error; both then believe they
  own the full VRAM — crash-loops or memory-pressure failures at runtime, on the worst
  possible mix (two 27B-class loads). This is not a degradation, it is a trap.
- The legitimate reading of the ask — two *lanes* each pinned to a different card — is
  served by pool arithmetic (P1: occupancy makes lane-2 take the other card) or, when a
  *specific* card per lane is mandatory, by the hostPath+ROCR idiom (P3) on one of the
  lanes.

---

## Contradiction map

| # | Claim A | Claim B | Ruling |
|---|---|---|---|
| C1 | `charts/radiance/values.yaml` comment: "each pool holds one device" | Live `amd.com/gpu-r9700-1: 2` (EXPLORE §0) | Comment stale — fix in the rename wave |
| C2 | HIP docs example: dashed NVIDIA-style UUID [16][17] | ROCR code renders/matches `GPU-%016X`, prefix 5–20 [11] | Code authoritative; dashed token can never match |
| C3 | Repo notes §4: ROCR is ordinal/index-only ("index law") | UUID matching present in ROCR ≥6.3 [14][15][19] | Notes incomplete (harmless for past observation); update note text |
| C4 | Intuition: kubelet hands plugins an ordered list | Kubelet passes `available.UnsortedList()` [8] | All determinism is the plugin's NodeId sort [5]; EXPLORE's "nodeId-ascending APU-first accident" note **corroborated** by BuildTopology order [13] |
| C5 | DRA README/develop advertises extendedResourceName + SPX classes [24] | Shipped v1.0.1 lacks them; source-install ships v0.1.0 image [22][30] | Docs-vs-shipped gap; pin plans to tags, not develop |
| C6 | DRA device attrs include productName [23] | #135: productName EMPTY on R9700 [28] | CEL must select on pciBusID only |
| C7 | cf-143 §R6/§R7 (sanitizer rules, filler-word list, `gpu-` prefix, collision→both-qualified, bare-`gpu`/empty→`amd.com/gpu` fallback, LoadProductIndex once+fatal, Allocate zero Env, kubelet capacity zeroing) | — re-verified at v1.31.0.12 / release-1.36 this round [1]–[8] | **All confirmed — no corrections to cf-143** |

## Implications for agent-plan

1. **Rename wave = one commit**: patched `amdgpu.ids` row (`r9700-1`→`r9700`), plugin
   untouched otherwise (no arg/image/version changes), every consumer values entry, both
   guard sweeps' needles (EXPLORE §2c/§2d), and the C1 comment fix. No chart version bump
   (hard rule; ConfigMap edit is the reload trigger).
2. **Write the determinism acceptance criterion in its true shape**: (a) a free single-card
   claim takes the lowest-KFD-NodeId card of its pool; (b) concurrent distinct claims take
   distinct cards; (c) a TP2 claim gets both cards; (d) *not* expressible: "lane X pinned
   to BDF c3" through the plugin. Any criterion of shape (d) forces a hostPath+ROCR lane
   (P3) or DRA (P6) and must be ruled by the owner, not assumed.
3. **No visibility env in radiance lanes** — plugin injects no env and the suite bars it
   [4]; adding engine-side flags would be dead config.
4. **strata/vllm hostPath lanes**: keep index pins + `HIP_VISIBLE_DEVICES=0` idiom +
   dated-receipt discipline (EXPLORE OQ-B's stance); UUID upgrade is opt-in only after
   OQ-R1.
5. **DRA**: zero chart work this ticket; record revisit triggers (OQ-R4) in DECISIONS.
6. **Live checks first** (cheap, read-only): OQ-R1, OQ-R2 below — both are one `kubectl
   exec` each against the amd-gpu pod; results feed the plan's receipt format.

## Open questions (no `question` tool in this role — owner rulings requested via plan round)

- **OQ-R1 — Do the R9700s expose a nonzero KFD unique_id?** Unverifiable from source
  (board/fuse-dependent) [19][20][21]. Check before any UUID pin:
  `grep unique_id /sys/class/kfd/kfd/topology/nodes/*/properties` (host, or exec into a
  pod with /sys mounted). **Best guess: nonzero on RDNA4, but must verify — a zero makes
  every UUID token silently match nothing (truncation law [11]).**
- **OQ-R2 — Which physical card (BDF c3 vs c7) has the lower KFD NodeId?** Determines
  which card the first single-card lane lands on. EXPLORE's ordinal data (0/1 = c3/c7)
  suggests probe order c3-then-c7 ⇒ **best guess: c3 wins**. One read of
  `.../nodes/*/properties` (`location`/`unique_id` lines) confirms; receipts should record
  the mapping, not assume it.
- **OQ-R3 — Rename timing:** land the rename inside this ticket's wave (recommended —
  the four-lane roster already rewrites consumers) vs a separate maintenance window.
  **Best guess: same ticket, one wave.**
- **OQ-R4 — DRA revisit triggers:** propose *release exists with `extendedResourceName`
  AND #75 closed* — revisit. **Best guess: owner accepts as a standing note, no action.**
- Carried (owner-owned, not research): EXPLORE OQ-A (hourly-runner model literal) and
  OQ-B (strata hostPath ruling) — research confirms OQ-B's "latter" reading is the only
  one consistent with the 2026-10-27 ruling and the source facts here.

## Sources

Numbered as merged by `storm_run.py merge` into the run's `sources.md` (41 URLs; deduped,
first-seen order). URLs point at pinned tags/branches as read 2026-11-22.

| # | Source |
|---|---|
| 1 | ROCm/k8s-device-plugin `cmd/k8s-device-plugin/main.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/cmd/k8s-device-plugin/main.go |
| 2 | … `internal/pkg/naming/naming.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/internal/pkg/naming/naming.go |
| 3 | … `internal/pkg/naming/products.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/internal/pkg/naming/products.go |
| 4 | … `internal/pkg/plugin/plugin.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/internal/pkg/plugin/plugin.go |
| 5 | … `internal/pkg/allocator/allocator.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/internal/pkg/allocator/allocator.go |
| 6 | … `internal/pkg/allocator/policy.go` @ v1.31.0.12 — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.12/internal/pkg/allocator/policy.go |
| 7 | k8s-device-plugin releases (v1.31.0.12 latest, 2026-11-06) — https://github.com/ROCm/k8s-device-plugin/releases |
| 8 | kubernetes `pkg/kubelet/cm/devicemanager/manager.go` @ release-1.36 — https://raw.githubusercontent.com/kubernetes/kubernetes/release-1.36/pkg/kubelet/cm/devicemanager/manager.go |
| 9 | Kubernetes docs: Device Plugins — https://kubernetes.io/docs/concepts/extendable-resource/device-plugins/ |
| 10 | Kubernetes docs: Resource Management for Pods and Containers — https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| 11 | ROCR-Runtime `amd_filter_device.cpp` @ master (ba56a24) — https://github.com/ROCm/ROCR-Runtime/blob/master/runtime/hsa-runtime/core/runtime/amd_filter_device.cpp |
| 12 | ROCR-Runtime `amd_filter_device.hpp` @ master — https://github.com/ROCm/ROCR-Runtime/blob/master/runtime/hsa-runtime/core/runtime/amd_filter_device.hpp |
| 13 | ROCR-Runtime `amd_topology.cpp` @ master — https://github.com/ROCm/ROCR-Runtime/blob/master/runtime/hsa-runtime/core/runtime/amd_topology.cpp |
| 14 | ROCR-Runtime `amd_filter_device.cpp` @ rocm-rel-6.4.1.2 — https://github.com/ROCm/ROCR-Runtime/blob/rocm-rel-6.4.1.2/runtime/hsa-runtime/core/runtime/amd_filter_device.cpp |
| 15 | ROCR-Runtime `amd_filter_device.cpp` @ rocm-rel-6.3 — https://github.com/ROCm/ROCR-Runtime/blob/rocm-rel-6.3/runtime/hsa-runtime/core/runtime/amd_filter_device.cpp |
| 16 | ROCm HIP docs: Debugging (visibility env) — https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/debug.html |
| 17 | rocm-docs `projects/HIP/data/how-to/debug.rst` @ master — https://github.com/ROCm/rocm-docs/blob/master/projects/HIP/data/how-to/debug.rst |
| 18 | rocm-docs `supported-env-vars.rst` @ master — https://github.com/ROCm/rocm-docs/blob/master/projects/HIP/data/reference/environment/supported-env-vars.rst |
| 19 | ollama commit d7c94e0ca6c3 (#7212, ROCR UUID identification) — https://github.com/ollama/ollama/commit/d7c94e0ca6c3 |
| 20 | Linux `amdkfd/kfd_topology.c` @ master (unique_id sysfs) — https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/amd/amdkfd/kfd_topology.c |
| 21 | Linux `amdgpu/amdgpu.h` @ master (`unique_id` field) — https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/amd/amdgpu/amdgpu.h |
| 22 | ROCm/k8s-gpu-dra-driver releases (v1.0.1 latest, 2026-07-22) — https://github.com/ROCm/k8s-gpu-dra-driver/releases |
| 23 | … `internal/device-plugin/api.go` @ develop — https://github.com/ROCm/k8s-gpu-dra-driver/blob/develop/internal/device-plugin/api.go |
| 24 | … `deploy/helm/…/device-classes.yaml` @ develop — https://github.com/ROCm/k8s-gpu-dra-driver/blob/develop/deploy/helm/k8s-gpu-dra-driver/templates/device-classes.yaml |
| 25 | dra-driver issue #75 (reboot breaks CDI, open 2026-11-11) — https://github.com/ROCm/k8s-gpu-dra-driver/issues/75 |
| 26 | dra-driver PR #78 (open, unmerged) — https://github.com/ROCm/k8s-gpu-dra-driver/pull/78 |
| 27 | dra-driver issue #86 (open) — https://github.com/ROCm/k8s-gpu-dra-driver/issues/86 |
| 28 | dra-driver issue #135 (k3s 1.36.6 + 2× R9700 field report) — https://github.com/ROCm/k8s-gpu-dra-driver/issues/135 |
| 29 | dra-driver issue #131 (release request) — https://github.com/ROCm/k8s-gpu-dra-driver/issues/131 |
| 30 | dra-driver issue #136 (v0.1.0 image bug) — https://github.com/ROCm/k8s-gpu-dra-driver/issues/136 |
| 31 | Kubernetes feature gates (1.36 DRA gates) — https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/ |
| 32 | Kubernetes v1.36 DRA blog — https://kubernetes.io/blog/2026-05-07/kubernetes-v1-36-dra-136-updates/ |
| 33 | Kubernetes DRA concept docs — https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/ |
| 34 | Kubernetes DRA features docs — https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/dra-features/ |
| 35 | radiance repo (Codeberg, main; RADIANCE_GPU) — https://codeberg.org/StillDeadcode/radiance |
| 36 | radiance `docs/DOCKER.md` @ main — https://codeberg.org/StillDeadcode/radiance/src/branch/main/docs/DOCKER.md |
| 37 | radiance `core/engine_bringup.cpp` @ main (`usable_devices`) — https://codeberg.org/StillDeadcode/radiance/src/branch/main/core/engine_bringup.cpp |
| 38 | vLLM `vllm/platforms/rocm.py` @ main — https://github.com/vllm-project/vllm/blob/main/vllm/platforms/rocm.py |
| 39 | level1techs 2×R9700 field guide — https://forum.level1techs.com/t/ultimate-2x-r9700-guide-for-qwen-3-8-27b-mxfp4-200t-s-c-1-500t-s-at-c-8/257789 |
| 40 | christopherpaquin/Radiance-vLLM-AMD-R9700 — https://github.com/christopherpaquin/Radiance-vLLM-AMD-R9700 |
| 41 | ROCm/k8s-device-plugin README (naming strategies) — https://github.com/ROCm/k8s-device-plugin |

---

## RESULT

- **agent**: agent-research
- **outcome**: done
- **next_suggested**: agent-plan
- **summary**: All six asks answered with source-grounded VERDICTs. (R-Q1) Pinned plugin
  has no visibility strategy and injects no env; single-card claims deterministically take
  the lowest KFD NodeId card (advisory-but-source-pinned at v1.31.0.12); TP2 gets both
  cards. (R-Q2) `ROCR_VISIBLE_DEVICES` accepts comma-separated KFD indices or `GPU-<16hex>`
  UUID prefixes (since ≥6.3); silent truncation on bad tokens; HIP/CUDA env index-only; no
  bus-ID form. (R-Q3) DRA = watch-list: 1.36 platform ready (DRAExtendedResource Beta on),
  driver v1.0.1 lacks the bridge, unstable names, open reboot/CDI bug #75; pciBusID is the
  only stable selector if ever adopted. (R-Q4) Pattern map P1–P6; pool arithmetic suffices
  for the four-lane roster; specific-card pinning only outside the plugin path. (R-Q5)
  Rename is one atomic wave; old name PENDINGs forever, running pods unaffected — EXPLORE
  §2b law confirmed with mechanism. (R-Q6) One card under two pool names: impossible via
  the plugin, double-booking via any side channel — rejected. cf-143 §R6/§R7 fully
  re-confirmed; 7 contradictions mapped (C1 stale comment fix rides the rename wave).
- **commands_run**: read-only research only — shallow clones into /tmp/opencode (ROCR-Runtime
  ×3 refs, DRA driver, radiance, HIP, rocm-docs), raw fetches of pinned source files, GitHub
  API issue/release/PR reads, k8s docs fetches, `storm_run.py init/merge`. No repo writes
  besides this file; no board or cluster mutation.
- **needs_info**: none blocking. Owner rulings OQ-R1..OQ-R4 (each with best guess) —
  OQ-R1 (KFD `unique_id` nonzero?) and OQ-R2 (NodeId→BDF map) are one-exec read-only live
  checks the plan should schedule before asserting UUID pins or card-identity receipts.
- **artifacts**: this file; storm intermediates (run dir above) with 41-source numbered
  `sources.md`, `contradictions.md`, `report.md`.
- **friction**: GitHub code-search API unauthenticated (401) and several proxied raw
  fetches 403 intermittently — routed around via shallow clones / API listings; no
  evidence lost. Kernel `unique_id` *population* sites remain unpin-downstream-reachable
  (sparse clones of kernel forks failed on auth) — honestly marked as live-check (OQ-R1)
  rather than source-claimed.
