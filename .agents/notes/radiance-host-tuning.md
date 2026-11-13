# Radiance gpu-ai host-tuning checklist — the owner's post-boot loop (C12)

**What this is.** The owner-executed host-tuning checklist behind the radiance
serving numbers: the engine's own startup reports (report 1: pre-streaming
budget 43.18 GiB; report 2: `pinned by this process 71.04 GiB`, first
request 5.1 tok/s decode / ~142 t/s prefill — the fresh 15:01Z boot re-read
printed the same hardware notes and 11.2 tok/s on its first request) are the
baseline receipts. Provenance: cf-143 `cf-143-feat-radiance-replaces-strata`,
chunk C12 (AC2); decisions D27/D28/D29; live probes EXPLORE §D2/§D4/§D6.
This is a CHECKLIST, not GitOps: the repo never tunes the host.

**Read-only law.** Every command below is read-only. Where a FIX is a host
WRITE (systemctl, cpufreq, sysfs, drop-ins), the line is framed OWNER-EXECUTED
prose — owner lane, owner's kubeconfig/ssh, never a repo step, never a
cluster mutation from this file. No pod-exec exists or is implied (AGENTS MCP
law). The acceptance gates (step-0 receipts, the naming assert, the
8-session bar) live in `.agents/notes/radiance-on-target-acceptance.md`
(C06) — this note is the one-variable-at-a-time tuning loop AFTER the boot.

**Assume nothing custom — the method.** The host's real posture is its
printed output, not the stock formula: quote `cat /proc/cmdline` into every
receipt, and take the engine's printed caps as the authority (the boot
pinned to a **112.00 GiB** TTM envelope — the printed `ttm.page_pool_size`
29360128 is exactly 29,360,128 pages × 4 KiB = 112.00 GiB; the
`ttm.pages_limit` 293610128 completes the pasted pair). That number, not
the stock RAM-minus-formula, is the envelope this note
measures against. This box runs a custom boot-parameter set —
the exact paste strings, verbatim: `amd_iommu=off amdgpu.lockup_timeout=30000
ttm.page_pool_size=29360128 ttm.pages_limit=293610128`. Re-read them on
every receipt; do not assume any of it survived a kernel update by accident.

## 1. LINK — the PCIe speed defect, PROVEN downgraded (first suspect)

Report token (both boots): `link-below-max: … runs 8.0 GT/s x4 of its
16.0 GT/s x4 while the card is 49% busy` — the WARN REPRINTED on the fresh
15:01Z boot, which is what PROVES the downgrade (§D6.6: report-2's silence
was luck/state; the retrain-vs-luck clause is CLOSED). Kernel boot line
verbatim: `31.504 Gb/s available PCIe bandwidth, limited by 8.0 GT/s PCIe
x4 link at 0000:00:03.1 (capable of 512.00 Gb/s-class 504.112 Gb/s with
32.0 GT/s x16)`.

Width vs speed, precisely: the **x4 width is PHYSICAL** here — the root
port's own LnkCap is 16 GT/s **x4** (OCuLink/SFF-8611 carries 4 lanes; the
"capable x16" class refers to the card silicon, unreachable through an x4
port); the switch internals (`c3:00.0`/`c4:00.0`, 32 GT/s x16) prove the
downstream is not the limiter. The only defect candidate is the SPEED:
Gen3 where the port caps Gen4. 3.94 GB/s raw ≈ HALF the RQ1-planned
7.0–7.2 GB/s class for this path (RESEARCH RQ1/RQ4 envelope) — which
predicts the ~142 t/s prefill signature, and why LINK is the FIRST suspect:
worth 2–4× prefill, vs the n-gram tier's 3–10% decode band.

Check (read-only): `sudo lspci -vvv -s 00:00:03.1 | grep -E 'LnkCap:|LnkSta:|LnkCtl2|TargetSpeed'`
— same for `0000:c2:00.0` — plus
`cat /sys/bus/pci/devices/0000:c2:00.0/current_speed /sys/bus/pci/devices/0000:c2:00.0/current_width`
and `sudo dmesg | grep -iE 'GT/s|link training|downgraded'`. The
discriminator is `LnkCtl2` **TargetSpeed**: TargetSpeed=8.0 ⇒ BIOS slot PIN
(fix: set the slot to Gen4/Auto in BIOS); TargetSpeed=16 while LnkSta reads
8.0 ⇒ Gen4 training failed on the electrical path — reseat/inspect the
Gen4-rated OCuLink cable or the retimer (fix: reseat/swap the cable,
owner lane). The reboot did NOT clear the state, which pushes toward
BIOS-pin-or-cable over transient-stick. A forced retrain (setpci LnkCtl
bit, or remove/rescan) is a WRITE — owner lane only. After any change: re-read the
startup report AND capture `GET /diagnostics` under a long prefill — the
link widths under load are the receipt.

## 2. MEMLOCK — 8 MiB in the container; the node-lane-only truth

Report tokens (reprinted 15:01Z): `RLIMIT_MEMLOCK is 8.00 MiB` + the
note memlock-limited line. **Probe correction first (§D6.3):** the earlier
16787369984 figure seen on the host is the PAUSE-SANDBOX limit
(`crictl inspectp` reads the sandbox, not the app container — it is
MemTotal/8 of the node, a computed default), NOT the container truth. The
engine's own `8.00 MiB` print IS the container rlimit by definition.

Read it correctly (owner host lane, read-only, no exec):
`cid=$(crictl ps --name radiance -q | head -1)` then
`pid=$(crictl inspect "$cid" | python3 -c 'import json,sys;print(json.load(sys.stdin)["info"]["pid"])')`
then `grep -E 'Max locked memory|Max open files' /proc/$pid/limits`. The
runbook's in-container twin (`/proc/1/limits`, step-0(d)) states the same
law from inside.

Why the number matters HERE and where it does NOT: the 71 GiB pool is
DRIVER-locked card-path memory — never ulimit-charged (D28 scope law).
RLIMIT_MEMLOCK gates only the RAM-ngram tier (arithmetically dead — §3) and
io_uring ring headroom. So: record it, do not chase it.

There is no per-pod route: no PodSpec field sets RLIMIT_MEMLOCK, it is not a
sysctl, and containerd's CRI config has no default_ulimits key (§D6.3,
upstream docs fetched) — the node lane is the only route, and the repo owns
the precedent: `.agents/notes/strata-host-prep-gpu-ai.md:115-118` —
a `[Service] LimitNOFILE=1048576 / LimitMEMLOCK=infinity` drop-in on
**k3s.service** (k3s hosts containerd), then daemon-reload and a k3s
restart. OWNER-EXECUTED (all of it): a restart rolls EVERY pod on the
node — schedule it in a radiance-down window; the staging marker exists,
so the init marker-skips (<1 s) after the roll. Target value `infinity`
(the upstream compose carries `--ulimit memlock=-1:-1`; 15.6 GiB is also
not enough). One nuance: the chart's IPC_LOCK capability bypasses the
rlimit for real mlock() charges, but the engine's tier gate reads the
PRINTED rlimit — whether it setrlimits first is an open engine-behavior
question, MOOT because §3 kills the tier arithmetically.

## 3. DIO-NGRAM — the RAM tier is arithmetically DEAD; disk spans are live

Report token (reprinted 15:01Z): `the filesystem reports no direct-I/O
alignment, so the n-gram table is read in spans of its block size, 4096
bytes; a direct read of one returned the file's bytes`. Owner's dd on the
same btrfs: `iflag=direct` measured **3.42 GB/s** — WORKS, but below the
runbook's own ≥5 GB/s gate bar (record, not a hard blocker; a bigger-count
or `fio` repeat separates btrfs-tax from single-stream depth).

The adjudication (so nobody re-files this as a probe bug): alignment
UNREPORTED ≠ direct I/O broken. `statx(2)` (man-pages 6.19): the
STATX_DIOALIGN regular-file fields are implemented by ext4, f2fs and xfs
ONLY — btrfs, under CoW, legitimately reports nothing; the engine's 4 KiB
span fallback is conservative policy against an absent hint.

KILL-LIST first: the RAM tier — `--ngram-placement ram` / a `ram=DIR`
shared table — pins the 47.68 GiB table on top of the 71.04 GiB already
printed: 71.04 + 47.68 = **118.72 > 110** (and > 96): ARITHMETICALLY DEAD
at both candidate limits, so unlocking MEMLOCK (§2) BUYS NOTHING HERE —
moot by the sum, not by opinion. Dropping `--kv-resident` to fund it
forfeits the 8-session lever — that is a profile negotiation with an owner
sign-off, never a scalar. The real options are: (c) STAY on disk in 4 KiB
spans (today's posture; published cost band 3–10% decode ≈ 0.3–1.2 tok/s
at the current 11.2 — second-order to LINK), or (a) move /models to
XFS/ext4 so statx reports alignment — a host STORAGE-LANE decision on the
SHARED 500Gi claim (it carries llama.cpp/strata/vllm data too; a chart
value cannot express it). Recommendation: stay (c); measure (a) only if
the band earns a device move AFTER the link fix. Checks (read-only):
`findmnt -T <pack-path>`, `sudo filefrag -v <pack> | head -20`, the dd
above.

## 4. GOVERNOR — the writes DID NOT PERSIST; persistence routes only

Host reads, today: all 32 CPUs `performance`/EPP `performance`, policy
2.00–5.19 GHz (owner's paste §3). Yet the FRESH 15:01Z boot's startup
report printed `note cpu-governor: the CPU governor is powersave with
energy preference balance_performance`. The engine's HARDWARE block is a
boot-time snapshot (RESEARCH RQ3) — and the reboot events mean the fresh
snapshot IS the current truth: the writes did not persist across the
reboot (non-persistence, not mere staleness). A runtime
`cpupower frequency-set` alone is therefore NOT the fix — that OWNER-EXECUTED
write reverts on the next reboot (there is no repo record of when the owner
set performance; their paste is the only evidence of the write).

Re-check (read-only): `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c`
and the same for `energy_performance_preference`, THEN the final authority:
re-read the engine startup report after a fresh boot (the pod restarts via
the owner's pod delete / rollout — Recreate, the marker makes the init a
<1 s skip). Persistence routes (each OWNER-EXECUTED, pick one and record
which): `systemctl enable --now cpupower.service`; a tmpfiles.d rule; a
udev rule on cpu hotplug; or the owner's tuned/tlp profile — a tuned/tlp
profile or the kernel parameter route if boot-time certainty is wanted.
Why-for-this-hot-path: decode steps are CPU-cheap but the PREFILL framing
and the sampler run on core 0; powersave EPP balance_performance parks
frequencies between bursts and the 49%-busy WARN window above is exactly
where it would show — record governor state beside every prefill receipt.

## 5. SWAP-ZRAM — expect empty; 425 MiB says otherwise

Check (read-only): `swapon --show`, `zramctl`. Target: NO active swap and
no active zram devices on a pinned-RAM serving box — the cgroup is the only
containment (the runbook's step-0(e) rows; the 425 MiB currently in use
makes this a live fix, not a formality). Fix is OWNER-EXECUTED:
`swapoff -a` plus, if zram is up, the mask `systemd.zram=0` kernel
parameter — NOT masking the generator units (RESEARCH Guide-corrections:
masking re-enables zram; `systemd.zram=0` is the lever). Why-for-this-
hot-path: pinned 71 GiB + a demotion burst that lands in swap is the
Wilde OOM class; swap-in latency also masquerades as decode stalls — rule
it out before chasing engines.

## 6. HUGEPAGES-TTM — the THP posture under a 71 GiB pin

Checks (read-only): `grep -E 'HugePages_Total|huge' /proc/meminfo`,
`cat /proc/buddyinfo`, `dmesg | grep -i -E 'compact|allocstall'`,
`grep -E 'compact_stall|compact_fail|allocstall' /proc/vmstat`. Today:
HugePages_Total 0 (no explicit hugetlb — fine, the driver arena is not
hugetlb-backed), but compaction pressure is on the record: compact_stall
117859, compact_fail 47681, allocstall_movable 116143, buddyinfo order-6
down to 112. What to watch: while the engine pins ~71 GiB for minutes at
first staging (tens-of-minutes class — §D4), large-order allocations lean
on compaction; a stall during that window is host memory work, not GPU.
This is also the family where the boot paste lives (HUGEPAGES-TTM line:
`ttm.page_pool_size=29360128` / `ttm.pages_limit=293610128` — the printed
112.00 GiB pin cap, the authority per the method section; kernel THP sysfs
`/sys/kernel/mm/transparent_hugepage/enabled` is a READ here — any WRITE
into it is owner-executed host lane). Do not "tune" THP speculatively:
change one variable, re-read the report, keep the numbers.

## 7. RUNTIME-PM — card power-state latency at first token

Check (read-only): `cat /sys/bus/pci/devices/0000:c2:00.0/power/runtime_control /sys/bus/pci/devices/0000:c2:00.0/power/runtime_status`,
`cat /sys/class/drm/card*/device/power_dpm_force_performance_level` if
present. Target today: `runtime_control` reads `auto` (the card is
runtime-PM eligible: it wakes on first use, which is the honest tax on
cold-start probes) — `d3cold` budget per device under
`/sys/bus/pci/devices/.../power/`. If decode probes on an IDLE pod show a
fixed ~first-request penalty that later requests don't pay, this family
owns it. Fix (a WRITE, owner lane): pin `runtime_control` to `on` via an
OWNER-EXECUTED sysfs write (echo on > the runtime_control file) or a udev
rule for persistence — one variable, re-read, compare the probe deltas.
Why-for-this-hot-path: a 5.1 tok/s reading taken right after idle is partly
a wake-up story, not a kernel story.

## 8. IOMMU — the gate was WRONG, not the host

The C06 runbook gate expected `iommu=pt`; that expectation was WRONG and is
superseded — the live posture is `amd_iommu=off` — and the engine WORKS on
it: report 2 prints `dma copy
lists` ACTIVE on DMA engine 0 (the supported fallback path; RESEARCH RQ3
S9: p2pdma is permissive on AMD root complexes; radiance runs no RCCL —
RQ4). So: the GATE was wrong, not the host; the acceptance runbook now
carries this same corrected posture (C12 folds it at step-0(e)) — the two
docs must not disagree, and `iommu=pt` is NOT required here. Re-verify
before any TP2/P2P experiment instead: `rocm-bandwidth-test` card↔card,
kernel config `HSA_AMD_P2P`/`PCI_P2PDMA` (RESEARCH RQ4 path). Recorded side
effect, no radiance action owed: off also bars the NPU driver — dmesg
carries `amdxdna … Running without IOMMU not supported` by construction;
if the owner ever wants the Ryzen AI NPU on this box, IOMMU-off is the
blocker. Their fact, their call.

## 9. PROVEN-DONE — do not redo these; they are receipts already

ReBAR/BAR0: the card's own total reads 31.86 GiB usable (the 32G BAR window
is in effect — step-0(e) receipt class, RESEARCH RQ3). CWSR:
`/sys/module/amdgpu/parameters/cwsr_enable` reads `1` (engine would refuse
otherwise — it booted). ECC-off: `mem_info_vram_total` 34208743424 B with
`ras_enable` 0. Kernel: 7.3.0-1-default (the 7.3.3 `mem_info_vram_vis_total`
regression caution stays UNRESOLVED and only bites a snapshot upgrade).
HIP/ROCm userland: report line HIP 7.16.26385. Product naming: the pod
claims `amd.com/gpu-r9700-1` from the patched-table pool and Scheduled
(D24/D26 surfaces) — the naming wave is live-good. The pack: hash-complete
(C11's repaired gate ran the first real `sha256sum` pass; §D4/§D6).

## 10. POWER-CLOCKS — 300 W cap is NOT the TP2 §3 120 W class

Checks (read-only): `cat /sys/class/drm/card*/device/pp_sclk_dpm_state
2>/dev/null; cat /sys/class/drm/card*/device/gpu_busy_percent`,
`rocm-smi --showclocks --showpower` if installed, plus the
`power_cap`/`power_cap_usd` fields the startup report prints (300 W class
here). Target: sclk must ramp to 2350 MHz under load — today the boot read
the 500–2350 MHz range with the card idle; CHECK THE RAMP under a running
prefill, not at rest. Distinguish honestly: the 300 W `power_cap` is the
slot's own ceiling and is NOT the ~120 W OCuLink cap class the TP2 doc §3
leaves open for a second card (that caveat belongs to `current_position`;
this card reads its full envelope). Low clock at 49% busy would be a
decode-side suspect after LINK; the report's 5.1→11.2 tok/s swing between
boots is exactly why clocks get their own re-read per receipt.

## 11. NUMA — there is no NUMA here

Checks (read-only): `numactl --hardware` / any `numa_node` reads: every
device reports **-1** — Strix's unified fabric has no NUMA split, so
interleave/policy tuning is MOOT on this box (RESEARCH RQ4's cross-die
discussion belongs to Threadripper-class rigs). Record the -1, spend no
variables here; the memory-side facts that DO matter are the pin cap (§6)
and swap (§5).

## 12. APU-VISIBLE — the 8060S is seen and not served, correctly

The engine enumerates the APU (gfx1151 in the startup device list; the
8060S card exists on PCI `c5:00.0`) yet radiance serves ONLY the R9700 —
correct by design: the pod claims the product-named `amd.com/gpu-r9700-1`
pool (D24), and `rocrVisibleDevices`/ROCR env is ABSENT in this lane (the
plugin's Allocate injects the device nodes; C02 absence law, RESEARCH
RQ3). The APU is the llama-swap ROUTER's engine (the 8060S pool, D21/D26
carrier). If a future report shows a radiance worker thread busy on
gfx1151, that is an enumeration bug, not a tuning knob — read the report's
device line and stop there. No hide experiments: `vfio-pci` on the APU
would strand the router (TP2 doc §5's interdependency, unchanged).

## 13. KV-STREAM-MISS — the ring's miss rate is working-state, not a fault

Report tokens: `kv-stream-miss: 459 misses this interval` alongside the
cumulative counters (6357 misses / 1.36M streamed) and the ring size
(16416 slots). What it means: KV groups evicted from card-side residency
that must stream back — on a 43 GiB pool + 8×200K resident mirror this
count WILL grow; it is a telemetry trend line, not a failure. Read-only
checks under load: re-read `GET /diagnostics` (live block, RESEARCH RQ3)
across a fixed ≥2000-token decode and watch the miss RATE per interval,
not the total. Target: no runaway acceleration at steady session count;
an interval that explodes while sessions are flat is the pool-vs-mirror
arithmetic (§14 and the C12 scalar comment) talking — that is a profile
question for the owner, never a sysfs chase.

## 14. HEAT-ENGINE — residency tiers never promoted: idle expert heat

Report tokens: expert-heat lines all zero — `0 dispatches`, `0 promotions`,
`0 demotions`, resident-per-layer `min 0 / max 154 / mean 54.4 / sd 73.3`,
layers L48+ resident 0 — plus the fresh boot's line quoted here
deliberately at this family: `expert prefetch resting: the steps used 29%
of its last 3528 copies, under the 30% that pays for them`. Reading: the
heat engine is IDLE because every expert already fits resident at 8×200K
under the 43 GiB pool — promotions/demotions only exist to move what
doesn't. The prefetch sitting below its pay-for threshold is the same
story in the other direction. Checks: re-read the report + `/diagnostics`
under a LONGER decode (≥2000 tokens, fixed probe) and after the session
count rises; target: zero stays correct while the pool holds — first
promotions appearing is HEALTH (pressure working), not a defect. If
demotion BURSTS coincide with RAM spikes, the pinned-burst class (RESEARCH
RQ1's Wilde note) is the thing to watch — it rides the same arithmetic
discussed at §3, not a host knob.

## 15. PROTOCOL — how to run the loop without lying to yourself

- ONE variable at a time. Boot receipts change tok/s between runs; the
  honest pairs are same-boot, before/after a single change.
- Fixed probe every time: the same prompt at the same depth — a ≥2000-token
  decode for decode numbers, one long prefill (≈55k class) for prefill —
  re-read the startup report AND `GET /diagnostics` under load (the live
  block; RESEARCH RQ3).
- The budget-line check before ANY memory conclusion (D28's class law made
  checkable): read the report's `pinned by this process … GiB` sum and
  compare it to the pod limit — the rule is limit ≥ pinned + 4 (the
  engine's ≥4-GiB-free-under-cgroup law). Today: printed pinned 71.04 vs
  the shipped guaranteedMemoryGi 110 pair → slack 38.96 ≥ 4 ✓. A limit
  below the printed budget is a DEFECT, never a ladder step — that is how
  the 64-era OOM happened.
- Suspect order (owner-impact-first): LINK → CLOCKS/POWER → RUNTIME-PM →
  governor PERSISTENCE → memlock/DIO (both parked: §2/§3 — memlock only
  ever buys the dead RAM tier).
- The acceptance bar is unchanged: the runbook's 8-session gate
  (`.agents/notes/radiance-on-target-acceptance.md`, step-6 gate). Tuning
  that regresses the gate is reverted, not argued.
- Cold-staging cost honesty (§D4): the first-ever pack hash ran tens-of-
  minutes class — 30–70 min at the 200m init cap C11 shipped under; the
  C12 1000m cap prices 8–23 min; the hash restarts at byte 0 on any pod
  loss, so never touch a pod mid-hash. The marker now exists: every
  restart is the <1 s skip. The host-side hash-and-touch loop-breaker
  (§D3b.6 era) remains human-owned, host lane, and is NOT a substitute for
  the shipped chart value.
