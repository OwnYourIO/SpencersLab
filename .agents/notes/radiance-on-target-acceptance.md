# Radiance on gpu-ai — host prep + on-target acceptance runbook (operator-owned)

**Posture (read first).** This file is operator-run: every step is an
observation, a receipt, or an OWNER-EXECUTED command — nothing in it mutates
the cluster repo-side, and the MANDATORY step-0 gates pass BEFORE anything
radiance-shaped runs. The owner's strata scale-down/restore is an
OWNER-EXECUTED protocol (Q10 verbatim: "I will manually scale down strata
when testing and using radiance") — the exact commands are recorded here for
convenience and are never a GitOps change (Q5's letter, DECISIONS D17).
Deployment stage is unchecked on this card: the cf-143 run ships no cluster
operation; this document is the owner's one-command-away on-target round
after the ticket branch merges and ArgoCD applies it.

**Provenance.** WeKan card #143 (`cf-143-feat-radiance-replaces-strata`);
feature folder `.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/`
— plan of record `2026-11-11-feat-cf-143-feat-radiance-replaces-strata.md`,
`DECISIONS.md` (D15–D24 + the owner Q7/Q9/Q10/Q11/Q12 rulings), `RESEARCH.md`
(cited below as `RQ<n>`, `§R6`, `R6-Q<n>`, `§R7`, `OQ<n>`,
`R6 OQ<n>` — every
reference resolves to a heading of that file), `EXPLORE.md`, `chunks/C06.md`,
`chunks/C08.md`. This file is C06 (its name/gate prose re-pointed by the C08
T-E docs sweep); the shipped values (`charts/radiance/values.yaml`,
`services/gpu-ai/prod/values.yaml`, `charts/amd-gpu/values.yaml`,
`.opencode/opencode.jsonc`) are the other numeric authority. Nothing is
quoted from the card's deployment guide — the guide's stale items are
corrected in RESEARCH's Guide-corrections table and stay corrected here.
Anything neither source answers is an `OPEN — measure` line, never a guess.

**Ground rules.** The cluster's only input is git: ArgoCD applies everything,
no step here runs a repo-side mutation and nothing instructs applying
manifests directly with kubectl (the repo's first hard rule). Host-side
commands run on the `ai-gpu` node (Tumbleweed + k3s); every kubectl line
here is READ-ONLY (`get`, `describe`, `logs`, `top`); pod-internal checks
run through the operator's own pod access — no agent tier grants pod exec
(RESEARCH RQ3; AGENTS MCP law). The two cluster mutations in the protocol
— the strata scale-down (step 3) and restore (step 10) — are OWNER-EXECUTED
out-of-band commands marked as such; the sync itself is ArgoCD's own
reconciliation, never a runbook instruction line.

**Scope belt (D21/B1).** Every gate here is gpu-ai-scoped. The gpu cluster's
plugin posture — the EXTERNAL amd-gpu chart 0.22.0 at 1.31.0.9, single
naming, bare `amd.com/gpu` claims — is INTENTIONAL per the owner's B1 shield
(DECISIONS D21), not drift; it owes no gates and no sysfs research in this
runbook.

## Step 0 — MANDATORY pre-deploy gates (gpu-ai host, before anything runs)

Nothing boots before these pass. Record every receipt in place (fill the
`[VERIFY:]` cells the way `strata-host-prep-gpu-ai.md` does); they are the
acceptance evidence trail, and several decide whether shipped values stay
correct or move by the ONE-scalar edits of step 6. The post-boot HOST-TUNING
loop — the fifteen owner-executed families (link, memlock, governor, n-gram
DIO, swap/zram, huge-pages/TTM, runtime-PM, iommu, clocks/power, …) with the
PROVEN-DONE list — lives in `.agents/notes/radiance-host-tuning.md` (C12):
the gates below stay the pre-deploy bar; the tuning note is the one-variable-
at-a-time loop AFTER the boot receipts, and the iommu/ReBAR/CWSR/ECC/zram
reads it shares with this file carry the SAME corrected posture in both.

**(a) — NAMING receipt (sysfs device+revision, both cards).** The amd-gpu
plugin's product naming maps each card to a resource name from the MINIMAL
PATCHED `amdgpu.ids` table — the ConfigMap `charts/amd-gpu` ships and mounts
over the image's baked file (the D24 lane ruling; derivation and mechanism
verified in the §R7 round, sanitizer §R6-Q1) — keyed by the PCI (device,
revision) pair the plugin
itself reads (§R6-Q1; RESEARCH RQ3 documents the enumeration). Prove the
pair from sysfs first:

```bash
for d in /sys/module/amdgpu/drivers/pci:amdgpu/0000:c4:00.0 \
         /sys/module/amdgpu/drivers/pci:amdgpu/0000:c5:00.0; do
    printf '%s device=%s revision=%s\n' "${d##*/}" "$(cat "$d/device")" "$(cat "$d/revision")"
done
```

Expected-name derivation — match the reads against the PATCHED table rows
(the ledger at `charts/amd-gpu/values.yaml`):

| read `device` | read `revision` | card | materialized pool name |
|---|---|---|---|
| `0x7551` | `0xc0` | Radeon AI PRO R9700 | `amd.com/gpu-r9700-1` |
| `0x1586` | one of `0xc1`/`0xc3`/`0xc6`/`0xd1` | Radeon 8060S (Strix APU) | `amd.com/gpu-8060s` |

Derive the names from the device reads, not from BDF position: the plugin's
KFD topology map enumerated `c4:00.0` as nodeId 0 / card1 / renderD128
(RESEARCH RQ3 — the APU-first class that crash-looped the vLLM lane), which
is why c4 is expected to read `0x1586`, but the pair is the authority. The
revision expectation itself is the §R6 residual this gate closes (R6 OQ1).

**Fallback trap + decision tree.** A (device, revision) pair the MINIMAL
patched table does not carry — by construction that is every pair beyond
this node's two cards' ten rows — lands THAT card under the bare
`amd.com/gpu` name (§R6-Q4's gate list, item a; RESEARCH RQ3 names the
reserved fallback). The pair is silently downgraded, the pod claiming the
named pool then never schedules. If a card reads a name you did not expect,
this is a decision tree, not a bug hunt — the owner's on-target call, two
sanctioned remedies:

- **Pin the claim by the materialized name**: one git edit moves the claim
  lines to the names the node ACTUALLY advertises (radiance's `requests`/
  `limits` in `charts/radiance/values.yaml`, llama-swap's gpu-ai overlay in
  `services/gpu-ai/prod/values.yaml`) — the flip list stays as-is.
- **Fix the table**: change what produces the names — add the actual
  (device, revision) row to the patched `amdgpu.ids` ConfigMap in
  `charts/amd-gpu/values.yaml` (git edit, then the receipts re-run; the
  rows' product string is what the sanitizer turns into the pool name,
  §R6-Q1). A bare-claiming node makes every named claim Pending, so this
  remedy must land before step 2 is called a pass.

Do NOT improvise a third path (hostPath env tricks would re-privileged the
pod against the Q7 ruling). Record the reads either way.

**(b) — request-sum receipt (the Pending-by-design gate).** Node allocatable
is ~125.08 GiB (RESEARCH RQ3, live S14 read). Sum the resident requests
against the new pod:

```bash
kubectl describe node ai-gpu | sed -n '/Allocated resources/,/Events/p'
kubectl -n default get deploy gpu-ai-llama-swap-strata \
  -o jsonpath='{.spec.replicas} {range .spec.template.spec.containers[*]}{.name}={.resources.requests.memory} {end}'
```

The shipped arithmetic (`charts/radiance/values.yaml` comment, restated at
the C12 value: `guaranteedMemoryGi: 110` — the owner ruling "110 GiB (your
figure)", D29): strata UP — radiance Guaranteed 110 + strata's 64Gi REQUEST
(its limits are 110Gi — requests are what schedule) + router and system
≈ 6.3 → 110 + 64 + 6.3 = 180.3 > 125.08, so a radiance pod beside a LIVE
strata sits Pending with "Insufficient memory" — that is the DESIGNED
handshake of the owner's manual scale-down protocol, loud and safe, never a
bug to fix by shrinking the chart (the 64-era 64+64+4=132 pair died with the
scalar; the handshake now INVERTS — at a scheduled 110, strata's
restore-back can never co-reside). Strata DOWN: 110 + router 4.125 + system
floor 1.158 = 115.28 ≤ 125.08 → it fits, 9.80 GiB free (§D6.2's exact live
terms; engine rule 110 − 71.04 printed = 38.96 ≥ 4). Radiance scheduling
REQUIRES step 3. Record the actual allocatable figure in place.

**(c) — GID resolution.** `/dev/kfd` and the render nodes decide the
service-block extension question:

```bash
getent group render video kfd
ls -l /dev/kfd /dev/dri/
```

Expected: this node's `/dev/kfd` and `/dev/dri/renderD*` are group **486**,
mode 660 (RESEARCH RQ3, live-verified; the GID-486 witness). The chart ships
`supplementalGroups: [486]` on that finding. Decision this receipt closes:
if the render nodes the plugin injects turn out to need a group BEYOND 486
for the dedicated UID, that is the one-edit `supplementalGroups` extension
through the service overlay (Deferred line) — record the groups, do not
pre-edit.

**(d) — memlock / nofile posture.** k3s inherits the systemd default:

```bash
systemctl show k3s -p LimitMEMLOCK -p LimitNOFILE
```

Expected receipts: `LimitNOFILE=1048576` — the k3s unit already sets 1M, no
drop-in owed (RESEARCH RQ3; the fd risk is llama-swap-CHILD only, and this
lane is a peer). `LimitMEMLOCK` unset → 8 MiB default: the card-path pins are
driver-locked user memory NOT charged to the ulimit; only the io_uring rings
are, and rings count per UID — the pod's dedicated runAsUser 65532 gets a
fresh 8 MiB budget (the llmkube/dsluo precedent, RESEARCH RQ3; the lab's own
strata pod pins ~100+ GiB arena on the same default, live RSS 73.9 GiB /
workingSet 109.05 GiB). Posture: no drop-in needed. The `k3s.service.d`
`LimitMEMLOCK` drop-in is OPTIONAL insurance — host-side, owner's lane, and
explicitly not a repo change. Post-boot re-read: inside the running
container (operator's own access) `grep -E 'Max locked memory|Max open
files' /proc/1/limits`.

**(e) — classic host gates (the rig checklist).** Engine-side verification is
built-in — the STARTUP REPORT prints BAR size, per-hop link widths,
ttm.pages_limit, cwsr_enable, memlock limits, cgroup limits and swap usage,
and `/diagnostics` re-reads live (RESEARCH RQ3) — but these host reads come
first:

| Check | Command (on the node) | Gate / record |
|---|---|---|
| ReBAR / BAR0 | `lspci -vv -d 1002:7551 \| grep -E "Region 0"` | expect the 32G-size BAR window (Above-4G + ReBAR on, RESEARCH Guide-corrections; the rig doc's own check) — `[VERIFY: printed Region 0 size]` |
| CWSR | `cat /sys/module/amdgpu/parameters/cwsr_enable` | must read `1` — the engine REFUSES startup otherwise (RESEARCH RQ3) |
| ECC off | `cat /sys/module/amdgpu/parameters/ras_enable; cat /sys/class/drm/card*/device/mem_info_vram_total` | expect `0` and `34208743424` bytes = 32,624 MiB (~31.86 GiB usable — the ECC-off recovery, RESEARCH RQ3) |
| iommu | `cat /proc/cmdline` | CORRECTED GATE (C12/§D6.6 — the old C06 line expected `iommu=pt`; the gate was WRONG, not the host): `amd_iommu=off` is the proven working posture for this engine's host-staging path (`dma copy lists` ACTIVE on DMA engine 0; no RCCL in radiance; the strata trio carrier strata-host-prep-gpu-ai.md §1.2) — record which is in effect; re-verify `rocm-bandwidth-test` + `HSA_AMD_P2P`/`PCI_P2PDMA` before any TP2/P2P experiment. Side effect: off also bars the NPU driver (`amdxdna … Running without IOMMU not supported`) — the owner's fact, their call, no radiance action |
| zram | `cat /proc/cmdline; zramctl` | `systemd.zram=0` is the real lever — masking the generator units RE-ENABLES zram (RESEARCH Guide-corrections); expect no active zram devices |
| swap | `swapon --show` | expect empty — swap-off/zram-off is the pinned-RAM discipline; the pod's containment is its cgroup ALONE (the 110Gi pair, C12/D29; strata's own cgroup-is-the-only-containment law). The engine's shared-memory tier ships capped at 2Gi emptyDir (chart `shm` block) — no host action |
| O_DIRECT (ngram disk tier) | `dd if=/dev/zero of="$(ls -d /var/lib/rancher/k3s/storage/*llama-swap* \| head -1)/.odirect-probe" bs=1M count=8192 oflag=direct && rm -f "$(ls -d /var/lib/rancher/k3s/storage/*llama-swap*)/.odirect-probe"` | the disk ngram tier REQUIRES an O_DIRECT-capable fs and the rig checklist wants ≥5 GB/s class (RESEARCH RQ1/RQ3) — record the MB/s; `[VERIFY: dd result]` |
| claim free space | `df -h "$(ls -d /var/lib/rancher/k3s/storage/*llama-swap* \| head -1)"` | ≥120 GiB free on the 500Gi claim before the 113.60 GiB pack stages (plan arithmetic; RESEARCH RQ0 pack bytes) |
| kernel pin | `uname -r` | lab sits at 7.3.0-1-default; the 7.3.3 `mem_info_vram_vis_total` regression is a CAUTION — re-check this gate before adopting any 7.3.3+ snapshot (RESEARCH Guide-corrections) |

The pinned-RAM ceiling all of this rides on: RAM − RAM/64 − 1.5 GiB ≈
**120.6 GiB** on this host (README-verbatim formula, RESEARCH RQ1).

## Step 1 — Names block + pin ledger (no placeholders)

| Name / pin | Value |
|---|---|
| Node / namespace / release | `ai-gpu` / `default` / `gpu-ai-radiance` (Deployment + Service carry the release name) |
| Served id (single authority, D7) | `qwen3.8-flash-next-radiance` — plus the wire-siblings `-urgent` / `-low` sharing the modelID (catalog rows, C05) |
| Peer URL (the ONE client route) | `http://gpu-ai-radiance.default.svc.cluster.local:8000` — no `/v1` suffix (request paths append verbatim) |
| Public chain (through llama-swap only) | `https://llama.spencerslab.com/v1` |
| GPU pools (gpu-ai only, D21 belt) | radiance claims `amd.com/gpu-r9700-1` (the patched-table name, D24); llama-swap claims `amd.com/gpu-8060s`; bare `amd.com/gpu` carries **zero capacity** there (§D2.2 kubelet retention: the key sits at 0 after the single-naming plugin was pruned — "absent" was the wrong word; the claim carrier moved per-cluster, C10/D26) — a stray bare claim on gpu-ai is still Pending-forever, the scheduler text literally `Insufficient amd.com/gpu`, loud by design |
| Shipped sizing scalars | `guaranteedMemoryGi: 110` (C12/AC1 — the owner ruling over D28's 96; the live receipt that moved it: the engine printed `pinned by this process 71.04 GiB` vs the old 64.00 cgroup) / `hostPoolMib: 43000` / `maxModelLen: 200000` / `maxNumSeqs: 8` (`charts/radiance/values.yaml` — the ladder moves these, one scalar per rung) |
| Engine image | `docker.io/stilldeadcode/radiance:1.17.0` — amd64 IMAGE-MANIFEST digest `sha256:6fb0e99bfb862e17cc15cb7b2f116c7dbdc831df59f82456a0691122e6cf5330`; tag INDEX (manifest-list wrapper) `sha256:c2acbaa373c89272ec47a22befa1cf04d2ddf1de51c2baf534f5273e517f7100` — which-is-which per RESEARCH RQ0, llmkube pins the manifest form |
| Plugin image | `docker.io/rocm/k8s-device-plugin:1.31.0.12` — amd64 digest `sha256:6437c74f6566e5d11c20c42369fca7194315943aea91f7bd6c98de1b19caf117` (`charts/amd-gpu/values.yaml`, §R6-Q5's verification receipts; the chart is first-party app-template since C08/D23 and ships the patched `amdgpu.ids` ConfigMap per D24) |
| Patched table | the `amdgpu-ids` ConfigMap in `charts/amd-gpu/values.yaml` — 10 data rows (1 renamed 7551/C0 `r9700-1` row + 9 carried 1586 rows), rows spliced from the fetched v1.31.0.12 baked file (authority `sha256:382ef0d5282fd8f5c17872c9f3641518d08a93e8c8e12b190e37005d48f3b1fa`, recorded in the test fixture header) |
| Pack | `/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad` — 113.60 GiB (121,969,901,568 B), lfs `sha256:0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20`, ungated (RESEARCH RQ0); staged on the shared `llama-swap` 500Gi claim |
| Peer route constants | `timeouts.responseHeader: 1800` (absorbs the cold-load class), `connect: 30`, set-if-undefined floor `"priority?": 5` (`services/gpu-ai/prod/values.yaml` peers.radiance, C04 evidence file) |
| Strata (stays live, Q5) | Deployment `gpu-ai-llama-swap-strata` — request 64Gi/8 cpu, limit 110Gi; runner route `gpu-ai/qwen3.8-flash-next-strata-q4` |

Digest pairing law: each ledger digest above appears 1:1 in its chart
(`charts/radiance/values.yaml`, `charts/amd-gpu/values.yaml`) beside the
`# renovate: datasource=docker` pin comment, or — for the patched-table
authority — in its test-evidence fixture header; runbook, chart ledger and
renovate pin pair the same way at every retarget; a digest retarget is a
DECISIONS line, not a drive-by (D2 posture; tag-rebuild caution on record).

## Step 2 — Flip-wave watch (post-merge, the naming receipts b–d)

The merge makes ArgoCD apply the flip wave: C07's naming commit plus C08's
first-party conversion land on main together, so one sync (1) retires the
old plugin DaemonSet and creates the renamed object (D23's documented
one-sync prune+create — the rename-set is enumerated in
`charts/amd-gpu/values.yaml`), (2) applies the patched `amdgpu.ids`
ConfigMap for the first time, and (3) flips llama-swap's overlay in the
same wave. Expect, in order:

1. The plugin pod rolls under the NEW object names — running GPU
   pods keep their allocations (container-creation-time; the plugin's own
   19-restart history proves no pod churn, RESEARCH RQ3). A seconds-long
   deregistration window between the old DaemonSet's prune and the new
   pod's registration is acceptable — it is the D23 strain, not an
   incident (lockstep law, §R6-Q4's row 4).

   ```bash
   kubectl -n default get pods \
     -l app.kubernetes.io/name=amd-gpu,app.kubernetes.io/instance=gpu-ai-amd-gpu -w
   ```

   THE C09 EXEC RECEIPT (D25 — the live crashloop class the fix closes):
   the pinned image ships no ENTRYPOINT, so without the chart's `command`
   key the args-only container execs its first flag and dies
   RunContainerError exit 128; the log and pool receipts below only fire
   once the binary actually starts. After the sync —

   ```bash
   kubectl -n default describe pod -l app.kubernetes.io/controller=device-plugin-daemonset \
     | grep -A4 -E "Command:|Args:|State:|Reason:|Restart Count"
   ```

   — expect `Command: /root/k8s-device-plugin`, the four `Args:` (the -v=5
   trio + the strategy flag), State: Running. Consequence while the plugin
   crashloops: NO node advertises `amd.com/gpu-r9700-1` or
   `amd.com/gpu-8060s`, and the radiance + gpu-ai llama-swap pods sit
   Pending on pool starvation (§D1.1) — after this fix, Pending there
   means the plugin is NOT Running, not a name defect (the pool names are
   the patched-table pair, D24; the step-0(a) receipts stand). D26
   supersedes the converse reading: a healthy plugin does NOT end the
   Pending story — item 4's third class exists.

2. Plugin log receipt — `-v=5` is what makes it runbook-log-bearing (the
   law lives in `charts/amd-gpu/values.yaml` now):

   ```bash
   kubectl -n default logs daemonset/gpu-ai-amd-gpu-device-plugin-daemonset --tail=200 \
     | grep -E "amdgpu.ids|Reporting .*devices as amd"
   ```

   Expect `Loaded 10 GPU products from /usr/share/libdrm/amdgpu.ids` —
   TEN, the MINIMAL patched table's data-row count (1 renamed 7551/C0 row
   + the 9 carried 1586 rows; source of the override: the rendered
   ConfigMap `gpu-ai-amd-gpu-amdgpu-ids`, data sha256
   `864da8694ab58ed8096e31dd49983736a130309b0ce058dfdf8bbe4fd843c6f5`
   (455 bytes as rendered — recompute from `helm template charts/amd-gpu`
   on any table edit) — plus "Reporting 1 devices as amd.com/gpu-…" per pool
   (§R6-Q4's fifth-receipt list, receipt b). Any other count means the
   overlay did not apply (or the table moved): the stock file is a
   different number — re-run the step-0 tree, do not proceed.

3. Node-status assert:

   ```bash
   kubectl describe node ai-gpu | grep -E "amd\.com"
   ```

   Expect `amd.com/gpu-r9700-1: 1` AND `amd.com/gpu-8060s: 1`, and the bare
   `amd.com/gpu` at COUNT 0 — the key is PRESENT at zero, not literally
   absent (§D2.2: kubelet retention of the pruned single-naming 1.31.0.9
   advertisement; "ABSENT" was the pre-C10 wording's wrong expectation).
   Read it as: a zero bare residue with both named pools at 1 = both cards
   matched the patched table; a NONZERO bare capacity without a
   single-naming history = a gate-(a) fallback fired → decision tree, step
   0. Receipt c of the same five-receipt list.

4. llama-swap post-rollout check: its Deployment template changed in the
   same wave, so the running pod serves until the replacement with
   `gpu-8060s` is Ready — then the startup log must STILL name the
   unified-vulkan APU serving path (receipt d; the image ledger line
   `charts/llama-swap/values.yaml`):

   ```bash
   kubectl -n default get deploy gpu-ai-llama-swap -o jsonpath='{.spec.template.spec.containers[0].resources}'
   kubectl -n default logs deploy/gpu-ai-llama-swap --tail=100 | grep -i vulkan
   ```

THE THIRD PENDING CLASS (C10/§D2.6.7 — supersedes the reading that a
healthy plugin ends the Pending story): plugin Running + both pools
advertised is NOT sufficient — `gpu-ai-llama-swap` can still sit Pending on
`Insufficient amd.com/gpu`, the CARRIER class. A bare claim inherited from
the chart's old tree-global default survived onto gpu-ai even where the
overlay "null"ed it, because deletion instructions are dropped in the
ApplicationSet→Application valuesObject chain before helm runs (D26), and
demanding a pool the node holds at capacity 0 is Pending-forever. Under
C10's claim-less chart + per-cluster positive ADDs the class is
structurally closed; if a claim-Pending ever recurs with healthy pools the
needle diagnostic is a valuesObject-vs-service-file diff — a `null` in a
service overlay does NOT retire an inherited claim, so check through the
live Application, never through a local `helm template`:

```bash
kubectl -n default get application gpu-ai-llama-swap \
  -o jsonpath='{.spec.sources[1].helm.valuesObject}'
```

The Applications live in namespace `default` — ai-gpu has no `argocd`
namespace, so a `-n argocd` read errors out. The shared appset
template gives every Application two sources in this order: source [0]
is the `ref: services` git source (values repo, no helm key), source [1]
is the chart's helm source whose `helm.valuesObject` ArgoCD renders
(`charts/base/templates/appset-charts.yaml:53-71`). If that order ever
changes, pick the source carrying the helm block.

Receipt e of that list — the radiance PCI/gfx1201 assert — is the step-7
belt-and-braces. If any of these watches fails, stop: this is still the
pre-deploy world (strata serves, radiance is Pending or absent), and the
rollback class for a failed naming wave is step 11(ii).

The overlay applies because the plugin plain-`os.Open`s the const
IDsPath
baked into the image by the Dockerfile COPY — the mechanism the §R7 round
verified. If a
future plugin image ever moves that file's location, the ConfigMap silently
stops applying and the baked-table name returns; radiance's claim then sits
Pending-forever. The receipts above are the catch: gate (a) expects the
patched pool names and receipt (b) counts the patched rows. A table edit
propagates with the DaemonSet rollout anyway — kubelet `subPath` never
live-updates and `LoadProductIndex` reads the file once at startup (the
chart values carry the same watch law, D24).

## Step 3 — Owner protocol: strata scale-down (Q10 verbatim)

Q10 verbatim: "I will manually scale down strata when testing and using
radiance." It is out-of-band by ruling — never a GitOps change, never a
repo artifact (Q5 letter). Record the RSS/workingSet baseline first —
`kubectl top pod` for the strata pod plus this node's `free -h` — because
the before/after delta IS the owner's "good metrics from Radiance" window
(step 10 records the other half).

SelfHeal note (ground truth, `charts/base/templates/appset-charts.yaml`):
the Applications sync automated with `selfHeal: true`, so an un-guarded
manual scale reverts at the next sync. Before scaling, SUSPEND auto-sync for
`gpu-ai-llama-swap` in the ArgoCD UI — OWNER-EXECUTED, UI-only, not a repo
change (the appset's `services.<scope>.selfHeal` annotation knobs are a git
edit; do not flip them for this protocol).

The scale-down itself (the exact command recorded for convenience; OWNER-EXECUTED on the owner's own kubeconfig):

```bash
# OWNER-EXECUTED — operator runs this, the repo never scripts it (Q10):
kubectl -n default scale deploy/gpu-ai-llama-swap-strata --replicas=0
```

The strata arenas drain and the ~110Gi working set releases (the ttl/cgroup
law of strata-host-prep-gpu-ai.md explains why the node breathes). Only NOW
does the pending `gpu-ai-radiance` pod schedule — the step-0(b) arithmetic
flips green the moment strata's 64Gi request leaves the node. Bring it up by
the normal route: ArgoCD's own reconciliation (or a UI-led sync of
`gpu-ai-radiance`) — the sync is the controller's job, never a runbook
command line here.

Live-grounded numbers (§D2.4 history — priced the 64-era pair: Σ running
effective requests 65.158 Gi against 125.08 Gi allocatable → free 59.92 Gi,
~4.08 Gi short of the then-shipped 64Gi, the designed `Insufficient memory`
to the byte with MemoryPressure=False). Restated at the C12 value: the
scale-down frees strata's 64Gi REQUEST → 110 + router 4.125 + system floor
1.158 = 115.28 ≤ 125.08 with 9.80 GiB free (§D6.2) and radiance schedules
on its own; the reverse never co-resides (110 + 64 + 6.3 = 180.3 > 125.08 —
the handshake inverts at 110, the cutover is a real either/or, D29).

OUTAGE TRUTH (D26): step 3 does not restore the router — with the pre-C10
carrier the outer llama-swap simply sits Pending on the third class (item
4; §D2.6.7 records the router down from 2026-11-13T01:52:09Z on exactly
this shape), and no scale-down moves a capacity-0 pool. The router returns
only with the C10 merge+sync: the Recreate replacement then claims
`amd.com/gpu-8060s`, which the node advertises at 1.

## Step 4 — Staging receipts (fetch-init + pack provenance)

The `radiance-fetch` init container stages the pack curl-resume style and
writes the `.staged-<lfs-sha>` marker ONLY after the portable `sha256sum`
equality gate passes (compute + shell compare, BusyBox-safe — the init
image's applets know no GNU long options, §D3b/D27) against
`0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20`
(the chart's own script, the ledger above). Receipts:

```bash
kubectl -n default logs deploy/gpu-ai-radiance -c radiance-fetch | tail -5
ls -ln "$(ls -d /var/lib/rancher/k3s/storage/*llama-swap* | head -1)/radiance/"
```

Expect the "radiance staging: complete" (or marker-skip) line and a listing
where the `.rad` and its marker are owner/group `65532:65532`. A re-check of
the 113.6 GiB file with `sha256sum` is a tens-of-minutes full read under a
throttled init (§D4: the busybox applet is single-threaded, no SHA-NI path,
CPU-quota-bound — 30–70 min at the 200m cap C11 ran under, 8–23 min at the
1000m cap C12 ships; not disk-bound at either) — run it
only if the marker is doubted (the init already gate-verified it).

Non-privileged-class FIRST TRAP — loud by design, not silent: the file must
be readable by the dedicated UID/gid through the fsGroup (`OnRootMismatch`,
`charts/radiance/values.yaml`). If the landed tree comes back root-owned
0600, the ENGINE container fails its model open at startup with a permission
error in the pod events/log — that failure is the receipt that the posture
is real; the fix is the init/ownership path, never a privileged shortcut
(Q7). The pod must NEVER mount hostPath device nodes — `/dev/kfd` and the
R9700 render node arrive via the named pool's `Allocate()` injection only
(RESEARCH RQ3; the chart's absence law).

## Step 5 — DRY_RUN args capture (rendered == shipped, read-only)

Compare what the cluster actually runs against the single source:

```bash
kubectl -n default get deploy gpu-ai-radiance \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="radiance")].args}' | tr ',' '\n'
```

The rendered args must equal the chart's `serveArgs` byte-for-byte — the
expectation below is that list as one shell line, extracted FROM
`charts/radiance/values.yaml` (retyping it here would break the equality
law; the contract suite diffs this block against the chart):

```text
--model /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
--port 8000
--host ::
--tp 1
--max-model-len 200000
--max-num-seqs 8
--placement expert_tiered
--host-pool-mib 43000
--gpu-headroom-mib 96
--kv-cache-dtype fp8
--kv-resident 32768
--num-speculative-tokens 3
--max-num-batched-tokens 4096
--checkpoint-interval 4096
--ngram-placement disk
--served-model-name qwen3.8-flash-next-radiance
```

Absence law is part of the needle: NO `serve` verb anywhere (the engine
takes args directly — RESEARCH RQ0), NO prefix-cache flag (mutually
exclusive with `--kv-resident`, D3/D17), NO api-key flag (keyless, D8), and
the stale guide's `expert-vs-cache-ratio` knob is absent because v1.17.0 has
no such flag (RESEARCH Guide-corrections). A mismatch here means the
service overlay or the chart drifted — stop, this is a git-class fix.

## Step 6 — Startup watch + the 8-session acceptance gate at FULL sizing

Watch the cold start: `kubectl -n default get pod -l app.kubernetes.io/name=radiance -w`
then follow the engine log. Expect, in this order:

- init `radiance-fetch` completes (step 4 receipts) → engine container
  starts;
- the engine loads its ~66 GiB working set — the 113.60 GiB pack minus the
  47.7 GiB n-gram table that stays streamed from disk (RESEARCH RQ0/
  Guide-corrections arithmetic). That read is MINUTES-class: the readiness
  gate is the startupProbe hitting `/health` every 10s for up to 180
  failures (the chart's 30-minute envelope — the llmkube probe law; probe a
  model endpoint and you run real inference on every kubelet tick, so the
  chart never does). The peer route's `responseHeader: 1800` absorbs the
  same class on the first request;
- a pod stuck Pending at this point is step-0(b)'s arithmetic still in
  effect — strata's request has not actually left the node (re-check step
  3, selfHeal included); that is the Pending-by-design handshake state, not
  an engine failure;
- the cgroup-limit WARNING line class (llmkube's observed "at 44Gi Radiance
  warned cgroup-limit" shape, RESEARCH RQ1): the engine refuses to start
  unless ≥4 GiB stays free under the memory cgroup after its reservations —
  at the shipped `guaranteedMemoryGi: 110` (D29) the printed 71.04 budget
  leaves 38.96 GiB of slack, so if THIS warning fires the PROFILE moved:
  read the printed tiers, sum them, compare to the limit (the budget-line
  class law, D28) before any scalar edit — a limit below the printed budget
  is a defect, never a ladder shortcut.

**The gate (RESEARCH OQ3 closes here):** the profile must START and then
HOLD 8 CONCURRENT 200K-class sessions on THIS host. The published refusal
("2×262k host copy does not fit beside the weights") was the reference rig,
a smaller host (RESEARCH RQ1) — the 124 GiB box is the ruling's bet; this
run is the datum. Pin the expectation for the receipt: the engine's own
printed budget is the authority — report 2 read `pinned by this process
71.04 GiB` (pool 42.70 + the kv-resident host mirror ~32 + arena 2.00 +
placement 1.18 + staging). The D17-era per-token arithmetic (mirror ≈19.3
at the ~12 KiB/token class → "60–70 GiB-class pins", the owner's
"60Gi-class" words) UNDER-RESERVED the mirror shipped 1.17.0 books
(~20 KiB/token at 8×200K) — D28 records the slip; the shipped scalar is
110 on the printed receipt (D29), never a per-token figure.

Eight-session fill skeleton (through the peer hop, long-context bodies,
step 9's chain): drive 8 concurrent sessions to the 200K-class depth while
`/stats` shows running/waiting fill; PASS = eight admitted without
refusal-class errors and decode steady.

The honest-envelope line, stated before any number is celebrated:
`--kv-resident` makes 8×200K RAM-fit and excludes the prefix-cache tier in
the same motion — every idle session's return re-prefills against the
Gen4-x4 wall (the 450–600 tok/s @55k class), the cost this acceptance
window pays knowingly (RESEARCH RQ1, the plan's risk law).

If the gate refuses, the ladder (every rung a DOCUMENTED OPTION, never a
shipped value; every rung is a ONE-scalar edit of the `charts/radiance/values.yaml`
scalars above, landed as a git change human-run and picked up by ArgoCD's
own reconciliation; re-run the gate after each):

- ladder UP (the ≥4-GiB-free rule or pin arithmetic bites): the C08-era plan
  `64 → 72 → 80 → 96` is CLOSED at the top — C12 landed the ceiling-plus
  outright (`guaranteedMemoryGi: 110`, the owner ruling D29: 110 + 4.125 +
  1.158 = 115.28 ≤ 125.08 strata-down, slack 110 − 71.04 printed = 38.96 ≥
  4). If a PROFILE change bites the rule again, re-walk the printed sums
  before choosing any new rung (budget-line law, not the old rungs). One
  scalar.
- ladder DOWN by pool first: `hostPoolMib` 43000 → 40000 → 36000. One
  scalar; experts spill back onto the card, KV room shrinks — measure the
  receipt line change.
- ladder DOWN by context next: `maxModelLen` 200000 → 128K-class (131072) →
  64K-class (65536) at 8 seqs. One scalar — but the catalog `limit.context`
  rows MUST follow the engine (true-axis law: the advertisement holds only
  while the shipped ctx does — a re-pin of 200000 is a paired edit).
- fewer live sessions: `maxNumSeqs` 8 → 4 — halves the reserved kv-resident
  host copy (reserved as max-num-seqs × max-model-len however short the
  requests, RESEARCH RQ1). This CONCEDES the 8-session acceptance target;
  it is a redefinition, an owner call recorded.
- LAST resort, explicit OWNER SIGN-OFF recorded: the mutually-exclusive
  prefix-cache-tier swap — drop `--kv-resident 32768`, add
  `--prefix-cache-mib 4096` (the v1.17.0 published 4-seq recipe: "few live
  + host-tier for idle", pool backs ~301K tokens ≈ 1.5×200K at 4 seqs,
  RESEARCH RQ1/Serving envelope). This is a serveArgs edit, not a scalar;
  it trades the acceptance target's shape and re-opens the Wilde
  pinned-demotion-burst class (step 9's note). The engine-side escape
  hatch recorded: `--prefix-cache-mib 0`.

Every rung moves ONE scalar (D15's single-source law is why the chart keeps
them as scalars); record which rung the receipts chose.

## Step 7 — STARTUP REPORT capture (the belt-and-braces naming assert)

The engine prints the STARTUP REPORT on success and on refusal (RESEARCH
Adjacent: unsupported configs print it and the pod fails LOUD — the repo's
exec-form boot-guard idiom mapped onto the engine). Capture from the pod log
and re-read live via `/diagnostics`:

- HARDWARE section PCI id == the R9700 (gfx1201) — the fifth naming receipt
  of §R6-Q4's list, kept as belt-and-braces: with
  per-name pools the scheduler choice is deterministic (§R6-Q4; D18 — the
  round-2 retry gate superseded), so a wrong-card read here means the
  fallback trap (step 0(a)) fired anyway;
- BAR size (ReBAR receipt corroboration) and per-hop PCIe link widths —
  SAMPLE UNDER LOAD: idle links park at Gen1 and a cold read misreports the
  fabric (RESEARCH RQ3; `/diagnostics` re-reads);
- the pool tokens line and the "the pool backs N% … M full-length sessions"
  elastic-pool line — per-token cost across ALL paged groups is what the
  startup log prints; PIN TO THAT RECEIPT, not to any per-token constant in
  the docs (the 7.32-vs-30-vs-60 KiB/token contradiction, RESEARCH RQ1, is
  resolved operationally exactly this way);
- the ttm / memlock / cgroup / swap lines (step 0(d)/(e) corroboration).

Bands, not constants, for what the run should measure (pre-registered —
these are expectations, not claims; RESEARCH RQ1/Serving envelope):
prefill on the OCuLink Gen4 x4 expects **450–600 tok/s at 55k-class depth**
(chunk 4096 ≈ 2× the chunk-2048 class; the 454-tok/s measurement on the
same link class is the anchor); single-stream decode ~30–35 t/s WITHOUT
speculation, higher with MTP accepted (the fn pack's native MTP-3 head,
RESEARCH RQ0). Record the measured numbers — they feed the follow-up cards
and the owner's metrics file.

## Step 8 — Priority/preemption live check (Q2 — the polarity proof)

Radiance's polarity is **higher-wins**: the catalog ships 9/5/1 (urgent 9 /
default 5 / low 1), the peer floor `"priority?": 5` is radiance's DEFAULT
class, and preemption takes victims from the sorted list's back — the
LOWEST priority first (RESEARCH RQ2). Proof on the live pod, through the
peer hop so the whole chain is exercised:

```bash
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next-radiance-urgent","priority":9,"max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next-radiance-low","priority":1,"max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
```

Then saturate the pool: concurrent bodies mixing priority 9 and priority 1
(long-context low, short urgent) under step 6's fill pressure. Expect the
URGENT (priority 9) traffic to schedule first and survive; read the victim
order through `/stats` plus `radiance:num_requests_preempted` /
`preempt_forced_total` (RESEARCH RQ2 names both; the vLLM-compat family
`vllm:num_requests_running/waiting`, `vllm:num_preemptions_total`,
`vllm:gpu_cache_usage_perc` rides `/metrics`). Overflow past
`--max-queued-requests` (default 8×max-num-seqs = 64 queued, RESEARCH RQ2)
answers 429 with a Retry-After header — a PASS on that is the graceful
degradation the card asked for.

**FAILS LOUDLY detector:** if the priority-9 urgent class is the one being
PREEMPTED while priority-1 low survives, the retired vLLM 1/5/9 numbers
were ported UNFLIPPED somewhere (the RQ2 inversion bug made real) — stop,
file it, do not "fix" the live check. Same stop if urgent shows
zero-pathology while a preemption sweep hits low last: the order must be
low(1)-first victims, urgent(9)-last, never the reverse.

## Step 9 — Serving smoke through the peer hop

Outer → `peers.radiance` → engine is the only client route (no ingress,
D8/internal-only trio skip). From the operator's node or any client:

```bash
kubectl -n default port-forward svc/gpu-ai-radiance 8000:8000 &
curl -s http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8000/metrics | grep -m5 -E "^vllm:|^radiance:"
kill %1
```

Through the chain (`https://llama.spencerslab.com/v1`): one tools-body
request (tool call parses and the round-trip function name returns) and one
reasoning-parse request — both prove the peer hop does not mangle the
payloads the catalog rows advertise (`tools: true` on all three radiance
rows). The eight-session fill skeleton from step 6 counts as chain smoke at
depth.

**Image-request leg (Q8 — the honesty leg).** The catalog rows advertise
`input: [text, image]` and the fn pack carries a vision tower (RESEARCH RQ0
pack facts / Adjacent: vision ships on) — but nobody in the corpus has a
published image-response receipt for THIS pack on THIS shape. Send one
image-bearing chat body through the chain. PASS = a parsed image response.
On FAIL: retire the catalog image-input claim right there — a
one-row-class edit flipping `"input": ["text", "image"]` to `"input":
["text"]` on the three radiance lines, recorded as the sanctioned rollback
of the Q8 ruling's marketing half (owner ruling Q8 + C05's stake: both
shipped surfaces point at THIS leg). The engine still serves text
perfectly; the advertisement is what moves.

`/metrics` sanity only here: the vllm-compat family is live and the two
existing vLLM-era dashboards are cheap re-import candidates — that is
FOLLOW-UP CARD #2 (Grafana re-import, Q6). Do NOT edit
`services/monitoring/prod/values.yaml` in this run; the dashboard question
rides the second Inbox card, not this window.

**Coexistence envelope (Q11 — observe, no auto-mitigate).** During
radiance-resident windows strata's R9700 arenas are UNAVAILABLE BY THE
OWNER'S OWN SCALE-DOWN PROTOCOL (step 3), not by contention — naming settles
cross-card choice, never VRAM arbitration (§R6-Q4; Q11's law). The one
engine-per-card observation still belongs in the owner's metrics file:
record `kubectl top pod` splits before/after each transition. The Wilde
pinned-demotion-burst class (RESEARCH Contradictions: experts reclaim VRAM
→ idle sessions demote PINNED in one burst, invisible to reclaim) applies
ONLY if the step-6 last-resort prefix-tier shape was adopted — it is MOOT
on the shipped `--kv-resident` profile. No GitOps mitigation exists for
any of it and none may be improvised.

## Step 10 — Restore-back (Q10's other half)

After testing, the owner reverses the protocol — same lane, same markers
(the scale command recorded for convenience, OWNER-EXECUTED out-of-band):

```bash
# OWNER-EXECUTED — operator runs this, the repo never scripts it (Q10):
kubectl -n default scale deploy/gpu-ai-llama-swap-strata --replicas=1
```

Then resume auto-sync for `gpu-ai-llama-swap` in the ArgoCD UI (the
step-3 suspend's counterpart). Strata's arenas re-pin ON DEMAND — the first
requests after restore pay the cold-pin minutes class (the ttl:3600
time-share law in strata-host-prep-gpu-ai.md), so verify the runner route
serves again through the chain:

```bash
curl -sS https://llama.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next-strata-q4","max_tokens":8,"messages":[{"role":"user","content":"ack"}]}'
```

A 200 completion means the hourly loop's runner literal survived the whole
ticket (Q5 kept strata live; Q4 kept radiance a NEW honest id — nobody
quietly moved the fleet's model). Record the workingSet/RSS split after
restore against step 3's baseline — that pair of deltas is the acceptance
file's tail: the owner's "good metrics from Radiance" set is complete only
with the before/after both sides.

## Step 11 — Rollback

Three classes, cheapest first — and the command law holds here too: this
step's repo moves are git changes human-run, picked up by ArgoCD's own
reconciliation.

**(i) radiance-only.** C04 wired radiance ADDITIVELY (every strata byte
untouched), so rolling the engine back is exactly two comment flips in
`services/gpu-ai/prod/values.yaml` — the `charts.radiance` entry and the
`peers.radiance` block — as a git revert/change PR. ArgoCD's prune removes
the `gpu-ai-radiance` Application on its own; llama-swap simply loses the
peer route (its own pods never depended on it). No naming-wave bytes move.

**(ii) NAMING WAVE — the lockstep-revert law.** One `git revert` RANGE over
the wave reverts the WHOLE of it — the flip shipped as a single commit
(D20: flip + chart + entry swap in one) and C08's first-party conversion is
the wave's second naming-bearing commit, so the range covers BOTH. NEVER
SPLIT THE PAIR: reverting the plugin entry alone restores `amd.com/gpu: 2`
on gpu-ai
but the gpu-ai OVERLAY flip leg (the `gpu-8060s` resources block, D21/B1)
must revert IN LOCKSTEP in the same range — a node advertising the named
pools beside a llama-swap already flipped to the APU name is fine, but a
reverted plugin beside an UN-reverted overlay flip strands the next
llama-swap restart on a name the node no longer offers (§R6-Q4's row 4 is
the migration/rollback authority). The C08 half reverts the same way on its
own when only the conversion must roll back: the DaemonSet swap is
name-mirror-image (the prune+create lands back on the old object names in
one sync). Check-out discipline: `git revert` of the wave's commits, one
range, one sync cycle.

**(iii) vllm re-enable (unrelated lane, for completeness).** The C01 disable
is fully reversible by uncomment: `charts.vllm` + `peers.vllm` in the
service file + the three `qwen3.8-27b-vllm` catalog rows, one PR. History
record: `gpu-ai-vllm` sat at 0 replicas out-of-band BEFORE the ticket —
this repo never added a `replicas: 0` key (owner Q3 ruling) — so whoever
zeroed it owns that fact (RESEARCH OQ6) and a re-enable sync returns one
replica with no GitOps archaeology.

## OPEN — measure (nothing above answered it)

- The 8×200K kv-resident start on THIS host (OQ3) — step 6's run is the
  first known datum anywhere; whatever it prints replaces the envelope
  arithmetic as the authority for the scalars.
- Measured prefill/decode on the lab's x4 at the shipped chunk — step 7's
  bands are expectation classes, not lab numbers.
- Whether a second concurrent image-pair request behaves differently from
  the single image leg — not sourced anywhere; record if tested.

*(end of runbook — every constant above mirrors the shipped charts/values at
merge time; if a file disagrees with this document, the chart is authority
and this document is the bug.)*
