# Strata on gpu-ai — host prep + enablement runbook (operator-owned)

**Provenance.** WeKan card #77 (`cf-77-feat-strata-llama-swap`); run-1 feature
folder `.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap/` — plan of
record `2026-10-27-cf-77-feat-strata-llama-swap.md` (human-owned steps 1–5 are
this file's skeleton), `DECISIONS.md`, `RESEARCH.md` (cited by §),
`chunks/C04.md`; run-2 folder
`.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap-1/` (the keyless and
in-chart-consolidation rulings this prose documents).
Perf/recipe source: PR #3636 fork `jiayeZhu/Strata@bench-strix-halo-r9700-022`
(bench results dated 2026-10-21, single machine — the epoch label on every
number below). Upstream issue references in this file: #2399, #2398, #3421,
#2706, #1715, #1128, #1250, #2257, #771, #1601, #4206, #3636
(Niko1221/Strata unless a llama-swap doc names otherwise). Fill the
[VERIFY]-marked cells in place as each gate is answered; every other value is
cited from the folder, not invented.

**Ground rules.** The cluster's only input is git — ArgoCD applies everything,
no step here runs `kubectl apply` or edits live objects; every values change
lands as a PR to this repo. Host-side commands run on the gpu-ai node
(Tumbleweed + k3s); the `kubectl exec`/`port-forward` lines are operator-run
(no agent tier grants pod exec).

## Step 0 — preflight fact sheet (read-only, before any prep)

| # | Check | Command | Gate / record |
|---|---|---|---|
| 0.1 | Distro + kernel | `cat /etc/os-release; uname -r; rpm -q kernel-default` | kernel ≥ 6.18.4; Tumbleweed rolls fast — [VERIFY: current series on-node] |
| 0.2 | Firmware | `rpm -q linux-firmware` | must NOT be `20251125` (bad MES 0x83 class, plan human step 2) |
| 0.3 | Devices present | `lspci -nn -d 1002:` | expect `1002:1586` (8060S) + the gfx1201 R9700 — [VERIFY: R9700 PCI-id string as printed] |
| 0.4 | OCuLink link | `lspci -vv -s <R9700>` → `LNSta` | `Speed 16GT/s Width x4` (~7.2 GB/s); a `Width x1` result pivots enablement to the Strix fallback (`charts/llama-swap/README.md`) |
| 0.5 | Link errors | same `lspci -vv`, AER block; `dmesg \| grep -i aer` | record correctable/uncorrectable counters; non-zero uncorrectable = repair the link before proceeding |
| 0.6 | Cmdline | `cat /proc/cmdline` | must eventually carry the `ttm.pages_limit` / `ttm.page_pool_size` / `amd_iommu=off` trio (§1.2) |
| 0.7 | TTM params live | `cat /sys/module/ttm/parameters/pages_limit /sys/module/ttm/parameters/page_pool_size` | both `29360128` after §1.2 + reboot |
| 0.8 | Device nodes | `ls -l /dev/kfd /dev/dri/` | kfd + renderD nodes exist (the pod hostPaths their sources) |
| 0.9 | Group GIDs | `getent group render video` | record both `gid=` numbers → §1.7 values path |
| 0.10 | MAC mode | `getenforce; aa-status` | expected: SELinux Disabled, AppArmor active (the plan assumed AppArmor, DECISIONS 2026-10-27 — this confirms or flips it, §1.8) |
| 0.11 | THP mode | `cat /sys/kernel/mm/transparent_hugepage/enabled` | record `[always]/[madvise]/[never]` — the #771 gate, §1.6 |
| 0.12 | k3s limits | `systemctl show k3s -p LimitNOFILE -p LimitMEMLOCK` | before §1.5 defaults are small; after, `1048576` / `infinity` |
| 0.13 | RAM | `free -g` | 128 GB total (R3); the arena math spends it with the llama.cpp trio idle |
| 0.14 | ROCm indices | `rocminfo` | gfx1201 index → `rocrVisibleDevices`; 8060S index → `rocrVisibleDevicesByModel[qwen3.8-flash-next-strata-strix]`; §1.9 |

## 1. Host preparation (human step 2; one-time, reboot before enabling)

### 1.1 Kernel and firmware

Gates 0.1/0.2. The `20251125` linux-firmware snapshot carries the MES 0x83
GPU-firmware failure class the plan excludes — anything else is fine, so the
check is the version, not a patch level. If 0.2 fails, roll back before
anything else: Tumbleweed's snapper + boot-menu snapshot entries can boot the
previous state, and at package level `zypper in --oldpackage
linux-firmware=<recorded-good-version>`, then `zypper al linux-firmware` and
`zypper ll` to confirm the lock — an unlocked firmware package silently
re-upgrades on the next `zypper dup`. [VERIFY: last-known-good version
on-node; keep the lock until upstream ships a fixed snapshot.]

### 1.2 Kernel cmdline (GRUB or sd-boot)

Target, verbatim from the plan's human step 2:

```
ttm.pages_limit=29360128 ttm.page_pool_size=29360128 amd_iommu=off
```

These size the TTM page pool for the pinned-arena path and drop the IOMMU
translation the guide's recipe ran without; the values are the recipe's, not
node-tunable. Which boot mechanism the node uses is [VERIFY] (`sdbootutil
list` succeeding means the systemd-boot path):

- sd-boot: `sdbootutil add-default-kcmdline "ttm.pages_limit=29360128"`,
  `sdbootutil add-default-kcmdline "ttm.page_pool_size=29360128"`,
  `sdbootutil add-default-kcmdline "amd_iommu=off"` —
  `add-default-kcmdline` persists across kernel updates, which a bare
  current-entry edit on a rolling distro does not.
- GRUB: append the three tokens to `GRUB_CMDLINE_LINUX_DEFAULT` in
  `/etc/default/grub`, then `grub2-mkconfig -o /boot/grub2/grub.cfg`.

Reboot; prove with checks 0.6 AND 0.7 — a build without TTM module parameter
support accepts the tokens silently and does nothing.

Tradeoff note: `iommu=pt` (passthrough) is the milder alternative — IOMMU
stays enabled for device isolation while DMA runs untranslated. The arena
recipe above was proven `amd_iommu=off`; `pt` mode is unproven for it.
`amd_iommu=off` also removes IOMMU domains other silicon may want (the 8060S
NPU, its DMA engines) — acceptable on a dedicated GPU node, a real cost on a
mixed-use host. [VERIFY: if this node must keep NPU/DMA consumers alive,
settle off-vs-pt on-target before the reboot.]

### 1.3 BIOS: UMA / ReBAR / ASPM

Three gates from the plan's on-target list; menu wording is board-specific —
record what the node's setup offers beside each:

- **UMA carve-out to its minimum** — the 8060S's fixed framebuffer steal
  comes straight off the 128 GB pool the arena math (§3.3) spends.
  [VERIFY: value set]
- **Above-4G Decoding / ReBAR enabled** — the gfx1201 BAR-mapping gate.
  [VERIFY: supported, final state]
- **ASPM disabled** — power-management latency gate. [VERIFY: supported,
  final state]

### 1.4 OCuLink

Gate 0.4 is the pivot: `LNSta` reads `16GT/s` at `x4` (~7.2 GB/s end-to-end)
→ the R9700 primary path proceeds. `x1` width (or no card at 0.3) → do not
enable the primary against a crippled link; run the Strix fallback instead
(`charts/llama-swap/README.md`, Strix-alone fallback). The AER counters in 0.5
separate a slow-but-clean link from an erroring one — re-seat or swap the
cable on uncorrectable counts, then re-test cold.

### 1.5 k3s systemd limit drop-in

```
mkdir -p /etc/systemd/system/k3s.service.d
printf '[Service]\nLimitNOFILE=1048576\nLimitMEMLOCK=infinity\n' \
  > /etc/systemd/system/k3s.service.d/10-strata-limits.conf
systemctl daemon-reload && systemctl restart k3s
systemctl show k3s -p LimitNOFILE -p LimitMEMLOCK   # re-run 0.12
```

Why both, PR #2399-open regime: no release self-raises the nofile soft limit
(#2398 found the fd ceiling and closed unmerged; its raise is the first
commit of the still-open #2399 — RESEARCH §2, contradiction #5), so the
engine cannot reach the fd count HIP pinned-memory creation needs, and the
container's `ulimit -n 524288` cmd wrapper can only raise the soft limit up
to this inherited hard ceiling. `LimitMEMLOCK=infinity` is the host half of
DOCKER.md's `--ulimit memlock=-1:-1`: the arena page-locks ~47 GiB and a
capped memlock fails the pin at load. The restart bounces k3s and every pod
on the node — schedule it.

### 1.6 Transparent huge pages

0.11 records the mode; #771 is the upstream issue class that makes THP worth
checking against the page-locked arena. [VERIFY: on-node mode and whether
#771's failure signature applies — change THP only via a persistent
mechanism (systemd unit / tuned profile), never an ad-hoc sysfs write the
next reboot erases.]

### 1.7 Group GIDs → chart values

`getent group render video` yields two `gid=` numbers. Ship them as the strata
pod's `supplementalGroups` — pod-shape keys ride the per-controller `pod:`
block (the tree-global `defaultPodOptions` would also re-shape the llama.cpp
main pod): `llama-swap:` block in `services/gpu-ai/prod/values.yaml`:

```yaml
app-template:
  controllers:
    strata:
      pod:
        securityContext:
          supplementalGroups: [<render-gid>, <video-gid>]
```

via a PR. The chart default is `[]` on purpose (nothing may start on guessed
GIDs); a non-empty list here replaces it through deep-merge. Same procedure
as §1.2's reboot — before sync, not after.

### 1.8 MAC mode

0.10 settles the assumption. Expected Tumbleweed/k3s state: `getenforce` →
Disabled, `aa-status` active — the plan rejected pre-baked `seLinuxOptions
spc_t` on that assumption (DECISIONS 2026-10-27). If SELinux is instead
enforcing on this node, the privileged pod needs `spc_t` handling before
sync — stop and route the change as a chart PR; do not patch in-cluster.

### 1.9 ROCm device indices → the two values keys

The supervisor injects `ROCR_VISIBLE_DEVICES` per model at render; the values
keys behind it are the only retarget path (never a template edit):

| Key | Feeds | Default | Finalize |
|---|---|---|---|
| `rocrVisibleDevices` | primary model env | `"0"` | [VERIFY] the gfx1201 index from 0.14 |
| `rocrVisibleDevicesByModel[qwen3.8-flash-next-strata-strix]` | strix model env | `"1"` | [VERIFY] the 8060S index; `"1"` mirrors PR #3636's dGPU-first enumeration — on a chip-only node the chip is `0` (set `"0"`) |

`rocminfo` maps indexes to silicon; the visible set after the filter must
contain exactly the one device each profile wants (proof rung 1 of the
validation ladder, `charts/llama-swap/README.md`). Spell indexes as quoted
strings in values — the template's sprig `default` treats an unquoted YAML
`0` as empty and silently inherits (C05 review nit). Both keys live in
`charts/llama-swap/values.yaml` (`strata.rocrVisibleDevices*`); the gpu-ai
service block overrides `rocrVisibleDevices`.

## 2. Staging weights on the shared claim (human-owned, before enablement 3.2)

The pod mounts the existing `llama-swap` 500Gi claim at `/models` (DECISIONS
Q3); Strata's files live under `/models/strata/`, kept out of llama.cpp's
`LLAMA_CACHE=/models` layout, in exactly the shape the profile args name
(`charts/llama-swap/values.yaml`, `strata.config.engineProfile.args`):

```
/models/strata/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf
/models/strata/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf   # PLE file (--ple-gguf)
/models/strata/packs/iq3_s/          # prepared pack — size UNCONFIRMED (RESEARCH §4; IQ3_XXS-class ~40 GB precedent)
/models/strata/mtp/rt/               # MTP draft layer ~6 GB
/models/strata/data/expert-profile.bin
```

The GGUF pair is 83.62 GB on disk (`ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF`
IQ3_S, two shards, revision `ed59f920…`; sha256s recorded in the upstream
repo's `model-manifest.json` — RESEARCH §4). Budget the area **135–160 GB**
(GGUFs + pack + MTP + headroom). Pack/MTP/expert-profile preparation is the
engine's own setup flow (upstream docs) — [VERIFY: exact prep commands on
this image]; this runbook fixes only where the results must land.

Capacity check before enabling: find the host directory backing the claim
(`kubectl get pv | grep llama-swap` → local-path storage dir) and `df -h` it
against the 135–160 GB budget. Page-cache note (#1250, shared-disk class):
the claim disk doubles as the IQ3_S page-cache floor — cached model bytes
read as used RAM but are reclaimable; under pressure
`sync && echo 1 > /proc/sys/vm/drop_caches` on the host frees them without
evicting anything live.

## 3. Enablement gate sequence (numbered; the first accepted request is 3.6)

**3.1 Host prep executed.** §1 complete, rebooted since any cmdline change,
Step 0 fact sheet re-run and still passing (0.6 + 0.7 prove the cmdline
actually took effect).

**3.2 ArgoCD sync — the consolidated Application (human-owned, repo law).**
Run the swap PR's one sync of `gpu-ai-llama-swap` only with the llama.cpp
trio idle AND strata cold: ArgoCD prunes the standalone `gpu-ai-strata`
Application and re-renders the one Application that now owns both pods —
the llama.cpp surface plus the strata controller's Deployment/Service
`gpu-ai-llama-swap-strata`, enabled by the seven keys flipped together in
`services/gpu-ai/prod/values.yaml` (chart default OFF; a partial set fails
the render by design). A cold prune is the precondition because a
prune-vs-create overlap against a pinned arena would double-pin the node
(§4). There is no secret gate anymore — the pod comes up lazy with no
prerequisites. Accepted cost of doing prune + re-render in one sync (Q-B
ruling): the strata route blips for seconds while the old Application's
Service disappears and the consolidated one propagates — a peers request
inside that window fails once and is retried. The llama.cpp surface never
blips; the reloader restart of the main pod on its config ConfigMap delta
is existing behavior on every config PR.

Pod Running; then the supervisor's health paths (port-forward per the chart's
NOTES.txt):

```
kubectl -n default port-forward svc/gpu-ai-llama-swap-strata 18080:8080
curl -s http://127.0.0.1:18080/health       # supervisor — answers while the arena is cold
curl -s http://127.0.0.1:18080/v1/models    # lists BOTH inner IDs
curl -s http://127.0.0.1:18080/running      # EMPTY — engine NOT loaded; lazy is the design (Q2)
```

`/running` non-empty here means something already pinned the arena before
the sizing gates closed — treat it as a failed gate and run the unload
escape (§4).

**3.3 Pre-first-request sizing checks (R3 math, trio idle).**

- `grep MemAvailable /proc/meminfo` plus `free -g` with the llama.cpp trio
  idle: MemAvailable must cover the shipped profile's implied budget —
  arena read measured 46.84 GiB + the conversation-cache budget (24576 MiB,
  16 slots, the PR's values — how it actually splits on this node is
  `--plan`'s answer) + KV/pack page-cache headroom, which together the
  `96Gi` pod request encodes (RESEARCH §4; `charts/llama-swap/values.yaml`
  resources comment).
- Total pod requests vs node allocatable — the strata pod must schedule
  alongside llama-swap's 4Gi:
  `kubectl describe node <gpu-ai-node>` → Allocatable block and the
  Requests summary; 96Gi + 4Gi under allocatable-minus-daemonsets, nothing
  else claiming the balance.
- No memory **limit** on the container is deliberate (#1601 posture) — a
  cgroup cap breaks the page-locked arena.

**3.4 R1 gate: `--plan` reconciliation (human step 3), before the first
accepted request.** The on-target finalizer, run per profile; repo numbers
are hypotheses until this output lands (R1 ruling):

```
kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- \
  /opt/strata/terminal/bin/strata serve --profile /profile/strata-iq3_s.json --plan --output json
kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- \
  /opt/strata/terminal/bin/strata serve --profile /profile/strata-strix-iq3_s.json --plan --output json
```

What the two runs **finalize** (the shipped values this gate is gated on):

- Primary (`strata-iq3_s.json`): `--expert-cache auto` → the resolved slot
  count for this node; the `--conversation-cache-mib 24576` × 16 slots
  budget against real 128 GB RAM (C02 sizing, R3); the tokenizer-shard and
  packaged-`lib_dirs` VERIFY markers (C02 declared them hypotheses for this
  gate).
- Strix (`strata-strix-iq3_s.json`): the `--expert-cache 24576 /
  --resident-budget-gib 55` hypothesis pair — no upstream source; the edit
  point is the VERIFY-marked block in `strata.config.engineProfileStrix.args`
  (RESEARCH §7, R1).

Deltas land as values edits in `charts/llama-swap/values.yaml`
(`strata.config.engineProfile*` renders verbatim to the profile ConfigMap —
never a template change), re-PR, re-sync. At the first real load also run
the #2706 startup-log gate on the strix profile (`STRATA_HC_UPMIX` —
procedure in `charts/llama-swap/README.md`).

**3.5 Timed-unload proof (same session, once the engine has loaded).**
`unloadTimeout: 180` is load-bearing: llama-swap force-kills at the per-model
unloadTimeout (global default **10 s**) long before the pod's 420 s grace
matters, and a ~47 GiB page-locked stop needs a wide window (RESEARCH §3,
contradiction #4). A `--plan` run does not load the engine — this proof needs
one real pin, so run it in a maintenance slot or fold it into 3.6's warm
session:

```
time curl -s -X POST http://127.0.0.1:18080/api/models/unload/qwen3.8-flash-next-strata
curl -s http://127.0.0.1:18080/running   # empty again
kubectl -n default logs deploy/gpu-ai-llama-swap-strata --since=10m | tail -50
```

Pass = a clean child exit inside the 180 s window: elapsed time plausible
for the arena size, logs show a graceful drain (the engine's own
`--shutdown-timeout` default 30 s), NOT a llama-swap force-kill, and the RAM
comes back (`free -g`). An exit at ~10 s means the raised value did not take
— stop, fix via values PR, re-prove. The escape hatch stays unproven until
this runs; the invariant `terminationGracePeriodSeconds 420 > unloadTimeout
180 + drain 30` must hold after any edit to either value.

**3.6 First Strata request — through the existing surface only, trio idle
AND strata cold, after the swap sync of §3.2 (RAM law).** `POST
https://llama.spencerslab.com/v1/chat/completions` with
`"model": "qwen3.8-flash-next-strata"` (bare inner ID routes per O1;
`strata/qwen3.8-flash-next-strata` always routes). The first request pays
the cold pin — minutes, absorbed by the 150×10s startup probe + inner
`healthCheckTimeout: 1800`; watch pod logs and `free -g` through it. The
full post-sync validation ladder (bench acceptance vs the RESEARCH §5
numbers, needle runs, cache reuse, `/v1/messages`, the keyless confirmation
of §3.7) is one document: `charts/llama-swap/README.md`, "Validation
ladder".

**3.7 Keyless confirmation (replaces the retired enforcement probe).** No
secret exists for this workload and none is sent: both run-config profiles
ship `api_key: "none"` and the inner supervisor runs the outer surface's
`apiKeys: []` posture. Prove the posture as a CHECK with §3.2's port-forward
still open — no Authorization header anywhere:

```
curl -s http://127.0.0.1:18080/health            # answers keyless
curl -s http://127.0.0.1:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next-strata","messages":[{"role":"user","content":"ping"}]}'
```

and one unauthenticated chat through `llama.<domain>` (§3.6's form). Pass =
all complete: the engine checks no key while it binds 127.0.0.1 and only the
supervisor proxy reaches it. A 401 at the engine means the shipped key
posture drifted from `api_key: "none"` — stop and fix via values PR; the
config-vs-env precedence question is exactly what this rung measures, do not
improvise an env-layer removal (the warm-session equivalent is the README
ladder's rung 6).

**3.8 Strays (operator tools after enablement).**

- Inner unload escape: `POST /api/models/unload/<id>` against the inner
  instance (port-forward above) — the only escape once the arena is warm.
- Preload flip (boot-pinned arena instead of lazy): the commented toggle in
  `charts/llama-swap/values.yaml` (`strata.config` model
  `hooks.on_startup.preload`). Never preload BOTH models — the `(p | s)`
  matrix alternatives swap-load each other
  (RESEARCH §3).
- `--kv-grow`: deferred per R4 — flip recipe §5.
- Strix mode selection: request the strix ID; when-to-use, perf epochs and
  the LPDDR5X budget law: `charts/llama-swap/README.md` (Strix-alone fallback).

## 4. RAM law — one-at-a-time discipline (Q2)

The engine posture is one at a time — the PR's one-at-a-time arm: no
`--batch`, `STRATA_PREFILL_CPU_SHARE=auto` (the `--batch 4` stall incident
after 85 min is why batch was rejected, DECISIONS Q2). The operational law
follows from the arena: once `qwen3.8-flash-next-strata` takes a request its
~47 GiB page-locked arena stays resident permanently (`ttl: 0`), and the
llama.cpp trio's ~90–119 GiB preallocation cannot coexist with it on 128 GB.
Therefore:

- No trio requests while Strata is warm; no Strata request while the trio is
  mid-session. Trio coexistence ends at the first Strata request.
- Peer models are invisible to the OUTER matrix (peers are not roster
  entries) — nothing enforces this automatically; it is operator discipline.
- Escape when the RAM is needed back: `POST /api/models/unload/<id>` on the
  inner instance (timed-proven at §3.5); the strix arena returns by itself
  after `ttl: 1800`.
- Rollout shape protects the same law: the pod uses `strategy: Recreate`
  because a RollingUpdate overlap would double-pin the arena — the #2257
  class the repo lived through 2026-10-18/19. Keep it; never schedule a
  second strata pod.

## 5. R4 — deferred `--kv-grow` flip recipe

Status: OFF. The shipped primary profile carries no `--kv-grow` (DECISIONS
amendment; RESEARCH §2/§5). Benefit: +13% experts in VRAM, +2–3% at 64K —
small, at the price of a real dependency:

- fd dependency: on HIP, kv-grow creates many virtual-memory handles. The
  PR's experiment failed `hipMemCreate` at chunk #1,017 with 31.8 GiB still
  free when the soft nofile limit was 1024. The cmd wrapper's `ulimit -n
  524288` — and the §1.5 host drop-in that makes that raise legal — is the
  mitigation. Prove the effect on the engine process, not a fresh exec
  shell (the wrapper applies to the engine child):
  `cat /proc/<engine-pid>/limits` → NoFile soft 524288, Max locked memory
  unlimited.
- trim risk (#1128 class): kv-grow grows and trims the resident KV region
  under pressure; the card guide's env mitigation `STRATA_KV_GROW_HOLD` is VOID:
  the variable does not exist upstream (RESEARCH §2 measured 0 hits;
  there is nothing to set, do not use it). The documented env alias is
  `STRATA_KV_GROW=1`; `--no-kv-grow` is the off-switch and `STRATA_HIP_VMM=0`
  disables the VMM backing if it misbehaves.

Flip = one values edit: add `- --kv-grow` to `strata.config.engineProfile.args`
(the commented re-add line is already in `charts/llama-swap/values.yaml`),
PR, sync, unload/reload, re-bench before accepting. The R4 ruling's posture:
the benefit is explicitly operator's-eyes-open — do not flip before §3.5's
unload proof passes.

## 6. Upgrades and bump cadence (coord ruling shape (b))

Strata upgrades are **manual**: the tag→digest ledger in
`containers/strata/README.md` is the bump record. Bump procedure (printed
there): inspect the new tag's digest → record tag+digest as a pair → one
commit changes both FROM tags → on-target `strata serve --plan` re-check
(§3.4) → re-bench. Releases and images are not in lockstep (0.2.4–0.2.6
shipped releases with NO images — RESEARCH §1); the GHCR tag list is the
only truth. `strata update` must never run inside the container — it
silently invalidates the ledger.

Expect renovate PRs anyway: the built-in dockerfile manager tracks the
literal FROM tags, and with one depName shared across both flavors the
candidates **bleed across flavors** (a gfx1151-flavored bump proposed
against the gfx120x line, and vice versa). Interim human rule (DECISIONS
coordination round): **close/ignore those PRs — never merge one**; bump only
against the ledger + re-bench, until a flavor-scoped versioning rule or
ignore lands (future ticket, STATE.json `deferred`).

## 7. Deferred modes and escalation record (not built; facts so nobody re-derives)

- **Split mode (8060S + R9700)** — deferred (STATE.json; plan Deferred).
  Flags: `--gpu-roles`, `--layer-split auto`; STRIX_HALO §5 role assignment
  (discrete card = Main, chip = Off); needs ≥0.2.1; `STRATA_HC_UPMIX` off
  per #2706 in that mode. The fork carries a working `split-0.2.2.json`
  config (RESEARCH §5). Trigger to reopen: short-prompt-dominated traffic —
  the guide's split win is only ≤4K uncached.
- **2B source-build container path** — escalation only if the bundled image
  fails on-target (RESEARCH §6; `containers/strata/README.md`, Escalation):
  `therock-dist-linux-gfx120X-all-7.14.1.tar.gz` exists on repo.amd.com
  (2.336 GB, no published sha — record the digest on download); against
  TheRock 7.14.1 the repo ships no gfx1201 hipBLASLt tuning table for
  100401, so a source build runs plain-dense prompt matmuls or self-tunes
  via `tools/hip/tune_hipblaslt.cpp`; PR #3636 ran gfx1201 on
  7.14.1/hipBLASLt 1.4.1 fine without a table — table ABSENCE on this arch
  is expected, no action (ladder rung 2).
- **`--memory-limit-mib` / cgroup handling (#1601)** — moot while the
  container carries no memory limit; revisit only if policy forces one.

## 8. Resolved-question ledger (where each ruling landed)

HITL kickoff rounds (the Q-space of each run's `DECISIONS.md`; full text
there):

| Q | Answer | Landed in |
|---|---|---|
| Q2 | lazy residency, `ttl: 0`, no preload; batch rejected | §4; `charts/llama-swap/values.yaml` model ttl + commented preload |
| Q3 | existing shared `llama-swap` claim via `existingClaim`, no new PVC | §2; chart persistence |
| Q4 | internal-only through `peers:` — no ingress (the deliberate trio deviation) | §3.6, §9; C03 wiring |
| Q8 | Strix-alone fallback IN SCOPE | C05; `charts/llama-swap/README.md` fallback section |
| C-A (r2) | keyless shipped default: `api_key: "none"` in both profiles; no secret prerequisite exists | §3.2 (ungated sync), §3.7 (proof) |
| C-B/Q-C (r2) | one Application owns both pods — in-chart second controller; standalone app prunes | §3.2; `charts/llama-swap/values.yaml` |
| Q-B (r2) | one-sync strata-route blip accepted (llama.cpp never blips) | §3.2 |

RESEARCH round (RESEARCH.md section headers, Q1–Q7): image facts §1 → C01
pins; serve CLI §2 → C02 profile design; peers §3 → C03; IQ3_S sizes §4 →
§2 here; PR configs §5 → primary profile + the acceptance numbers; TheRock
§6 → §7 here; STRIX_HALO §7 → C05.

Peers/timeout questions: **O1** naming — `strata/<id>` always routes, bare
ID while exactly one peer serves it and nothing shadows it (RESEARCH §3) →
§3.6; **O2** cold load — outer per-peer `timeouts.responseHeader: 1800` ≈
inner `healthCheckTimeout: 1800` → the C03 peers entry.

Research-ruling round (STATE.json `research_answers`): **R1** upstream-plan
gate → §3.4 (this runbook's `--plan` step finalizes C05's hypothesis pair
and C02's sizing); **R2** vision OFF for v1 → documented commented toggle
(`--vision` line in `strata.config.engineProfile`); **R3** 128 GB sizing
math → §3.3; **R4** `--kv-grow` deferred → §5.

## 9. Post-sync validation — where it lives

The validation ladder is documented once, in `charts/llama-swap/README.md`
("Validation ladder"): devices/ulimits proof in-pod, startup-log
fingerprints, 4K/16K/64K curls through the outer surface, the consented
one-attempt `strata bench run --suite standard-v1` acceptance vs RESEARCH
§5's one-at-a-time column within ~10%, conversation-cache reuse, the
`/v1/messages` smoke + keyless first-request confirmation (§3.7), and the
128K/200K needle runs with `dmesg`/`free` watched. Readiness for it starts
at 3.6; the one-attempt protocol inherits the flash-next OOM ticket's
posture (plan Deferred).
