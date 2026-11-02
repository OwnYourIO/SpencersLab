# Debug investigation: pve-main overnight offline events after PVE update

- Date: 2026-11-02
- Type: debug (investigation only — no repo changes; all recommended actions are user-owned on the PVE hosts)
- Status: root cause identified with high confidence; host-side confirmation pending (`journalctl -b -1 -k` on pve-main)

## Symptom

pve-main went offline overnight repeatedly right after the lab's PVE update to kernel
`7.0.14-26-pve` (from `6.17.13-2-pve`), taking its VMs — the home-lab/grow/media k8s nodes and
others — down with it. Home Assistant (on the home cluster) was down through the same windows and
recovered on its own after the Nov 2 morning reboot.

## Timeline (all times local America/Denver; UTC in parentheses)

| When | Event |
|---|---|
| Oct 31 ~5:59 PM MDT (23:59Z) | pve-main reboots into new kernel 7.0.14-26-pve (the update). pve-gpu 6:10 PM (00:10Z), pve-infra 6:41 PM (00:41Z) follow. pve-monitor stays on 6.17.4-2-pve. |
| Oct 31 7:32–8:12 PM MDT (01:32–02:12Z) | ~110 MB/s bidirectional (≈1 Gbps full duplex, 40 min) burst on pve-main's USB NIC `enx00e04c0601d3`, mirrored by `tap120i0` (VM 120). |
| **Oct 31 ~8:35 PM MDT (02:33–02:37Z)** | **pve-main dies suddenly** — last metrics 02:36–02:38Z; no temp/memory/PSI distress in the samples before death. Reboots itself (or is power-cycled) — boot 8:47 PM MDT (02:47Z). Post-boot VM autostart storm: load 22, coretemp spikes to 99 °C, VMs home-lab/grow/media boot 8:50 PM (02:50Z). |
| Nov 1 2:00–2:42 AM MST (09:02–09:42Z) | Nightly job: sustained ~208 MB/s NVMe read storm (IO queue weighted 9–16; NVMe 46→61 °C). |
| Nov 1 2:42–3:03 AM MST (09:42–10:03Z) | Load shifts to `sda`: 155–206 MB/s reads, IO queue saturated (weighted 11). |
| **Nov 1 ~3:03–3:06 AM MST (10:03–10:06Z)** | **pve-main hard-freezes** — metrics stop mid-normal-samples (load 11, coretemp 80 °C, PSI ~1%). Down ~2.5 h; brief partial boot ~4:55–5:02 AM (11:58Z, load 0.3); dies again; VMs boot 5:25 AM (12:25Z); final stable boot 5:35 AM MST (12:35:53Z) — consistent with manual power cycles. |
| Nov 1 ~5:31 AM MST (~12:31Z) | pve-infra also drops (metrics healthy to 12:30Z, load 2–4), reboots, boot 5:49 AM (12:49Z). Cause of its drop not visible remotely. |
| Nov 2 2:00–2:42 AM MST (09:02–09:42Z) | Same nightly NVMe read storm (208 MB/s, identical shape). |
| Nov 2 2:42–3:34 AM MST | Same sda takeover (up to 208 MB/s, weighted 11 saturated). |
| **Nov 2 ~3:40 AM MST (10:40Z)** | **pve-main dies again.** Down 3h11m; boot 6:51 AM MST (13:51Z); VMs boot 6:54 AM (13:54Z); HA core back up ~6:56 AM. |

Control: the **same backup read storms ran Oct 27–28 on the old kernel (6.17.13-2-pve) with no
crash** — pve-main was up 3.9 days straight, surviving an identical 08:10–11:00Z storm on Oct 28
and a 112 MB/s NIC burst on Oct 29.

## Evidence gathered (read-only: Grafana MCP → Prometheus/Loki, HA MCP, web)

- Prometheus `up`/`node_boot_time_seconds` gaps and boot transitions for all four PVE hosts (7d).
- `node_uname_info` release transitions: pve-main/gpu/infra → `7.0.14-26-pve` on Nov 1; pve-monitor
  still `6.17.4-2-pve` and stable since Oct 26.
- Pre-death profiling both freeze windows: `node_load1`, `node_memory_MemAvailable_bytes`,
  `node_pressure_{io,memory,cpu}_*` (PSI), `node_disk_*` per device, `node_network_*` per device,
  `node_hwmon_temp_celsius` — **no OOM, no PSI stall, no thermal spike at death**; deaths are abrupt
  under heavy read IO / right after heavy NIC bursts.
- Topology: pve-main's entire LAN runs on USB Ethernet `enx00e04c0601d3` (onboard `enp0s31f6` and
  second USB NIC `enx64c901acc061` carry zero traffic; host also has WiFi `wlp112s0` + WWAN). VMs
  103, 107 (2 NICs), 111, 112, 116, 120 bridge through it. pve-infra's only wired NIC is also USB
  (`enx38ca84542cdb`); pve-gpu likewise (`enx9cbf0d008f6e`). USB NIC drop rate constant (~0.42/s,
  benign), zero error spikes, no carrier flaps before deaths.
- Loki journald (k8s nodes only; PVE hosts do not forward logs): dracut boot markers prove
  home-lab/grow/media are VMs on pve-main (boots lockstep with host: 00:02Z, 02:50Z, 12:25/12:38Z
  Nov 1; 13:54Z Nov 2). The infra node VM self-rebooted 02:12/03:03/03:23Z Nov 1 while its host
  stayed up — normal MicroOS transactional-update/rebootmgr behavior, not host instability.
- No ZFS pools active on any host (`node_zfs_arc_size` = 3840 B idle footprint on all four;
  `node_zfs_zil_zil_commit_count` and `node_zfs_dmu_tx_dmu_tx_assigned` flat zero across 7 days —
  covering the pre-update Oct 28-31 boot session and all post-update boots); storage is LVM (dm-*)
  on NVMe + sda. No smartmontools metrics exported. The staff-confirmed -26 ZFS-recv deadlock is
  therefore NOT the pve-main mechanism; the regression stands on the timing/upstream evidence.
- Upstream reports on exactly this kernel:
  - Proxmox forum, staff-confirmed: "Kernel 7.0.14-26 makes zfs replication hang on receive"
    (forum.proxmox.com/threads/…187369) — `zfs_rezget()` backport (openzfs/zfs#19013, shipped in
    -26 to fix PVE bug 7653) introduces an ABBA folio-lock vs `z_teardown_lock` deadlock; any
    concurrent read load hangs the pool and blocks soft reboot. Staff (t.lamprecht, Oct 31):
    reproduced, fix being assembled upstream, **workaround: boot 7.0.14-25**.
  - Proxmox forum/Reddit: "Hang on Boot with Kernel 7.0.14-26" (Protectli VP4670 mini PC — same
    hardware class as pve-main's USB-NIC/WiFi/WWAN box); boots fine on 7.0.2-6.

## Root cause assessment

**Primary hypothesis (high confidence): kernel `7.0.14-26-pve` is a bad release for this hardware;
pve-main hard-fails under its backup workload on it.** The workload (2 AM nightly backup: 40 min of
~208 MB/s NVMe reads → sda saturation → upload; plus evening ~1 Gbps USB-NIC bursts from VM 120)
is unchanged and survived intact on 6.17.13-2-pve four days earlier. Deaths began only after the
update, recur nightly in the backup window, and 7.0.14-26 has staff-confirmed hang regressions and
an independent boot-hang report on mini-PC hardware. pve-main has no ZFS pool, so the specific
zfs_rezget deadlock is likely not the exact code path — the exact mechanism needs pve-main's
previous-boot kernel log (hung_task/BUG/rcu-stall traces, r8152/xhci USB messages), which is not
forwarded to Loki.

Secondary observations (not the trigger, worth fixing):
- Chronic thermals: coretemp 73–84 °C at idle/low load, 99 °C spike during VM autostorm — this box
  runs at the thermal edge; clean fans/repaste.
- The 2.5 h and 3 h outages imply no watchdog/auto-recovery: freeze → dead until someone power-cycles.

## Recommended actions (user-owned; no admin access from agent sessions)

1. **Capture evidence before it rotates** (on pve-main):
   `journalctl -k -b -1 --no-pager | tail -300` (repeat for `-b -2`, `-b -3`) — look for
   `INFO: task … blocked for more than N seconds`, `BUG:`, `rcu_sched`, `r8152`/`xhci_hcd` lines at
   the tail of each dead boot. Also `journalctl -b -1 -u pve*vzdump*` / `grep -c . /var/log/vzdump/*.log`.
2. **Pin the known-good kernel** (staff-recommended workaround):
   `proxmox-boot-tool kernel list`, then `proxmox-boot-tool kernel pin 7.0.14-25-pve` (or
   `6.17.13-2-pve`) + reboot; do the same on pve-infra/pve-gpu (both on -26). Unpin once Proxmox
   ships the fixed kernel (watch the forum thread / pve-enterprise changelog).
3. **Identify and pause the 2 AM job until pinned**: `cat /etc/pve/jobs.cfg` (vzdump schedule),
   `systemctl list-timers`, cron.d — and identify VM 120 (`qm config 120`) whose evening ~1 Gbps
   bidirectional burst preceded crash #1.
4. **Forward PVE host journals to Loki** — Alloy already runs on the hosts for `integrations/unix`
   metrics; add a `loki.source.journal` for the host itself so the next event is diagnosable without SSH.
5. **Thermals**: inspect cooling on pve-main (idle 75–84 °C is too hot for sustained reliability).
6. Optional resilience: a watchdog (hardware or `softdog` + panic-on-hung-task
   `kernel.hung_task_panic=1` + `panic=30`) would turn 3-hour freezes into 5-minute reboots.

## Verification

- Investigation only; no repo files changed besides this report. All findings derive from live
  read-only queries (Grafana MCP: Prometheus/Loki; HA MCP) and linked upstream reports.
- Post-fix verification: after kernel pin, confirm `node_boot_time_seconds{instance="pve-main"}`
  stays constant across ≥3 nights spanning the 09:00Z backup window, and that home-lab/grow/media
  dracut markers show no overnight boots.

## Addendum: gpu-ai + dev cluster outages (same incident, DHCP cascade)

The `gpu-ai` and `dev` k8s clusters dropped ~1 h after each pve-main freeze (Nov 1: dev 11:30Z,
gpu-ai 11:55Z → both recovered 12:40-12:45Z, minutes after pve-main's 12:35Z boot; Nov 2: both
11:40-11:45Z). Mechanism, from their own journald in Loki:

1. The machines stay powered and networked (journals flow uninterrupted through both pve-main
   outages — they are not VMs on pve-main; dev is a VM elsewhere — `ens18` virtio; ai-gpu is a
   bare-metal 32-CPU box — `enp191s0` + WiFi).
2. When the renewal of their short DHCP lease hits T1 (~1 h) while the primary DHCP server (which
   lives on pve-main) is dead, NetworkManager rebinds and a different responder hands out a
   DIFFERENT address: ai-gpu got `10.0.99.152` instead of `10.0.99.151`; dev got `10.0.77.71`
   (Nov 1) and `10.0.77.131` (Nov 2) instead of `10.0.77.12`.
3. Their k3s identity is bound to the old node IP: kubelet `failed to validate nodeIP: node IP
   "10.0.77.12" not found`, remotedialer `dial tcp 10.0.77.12:6443: no route to host` → apiserver/
   kubelet/cadvisor scrapes fail → cluster shows offline while the OS is fine.
4. Nov 1 self-healed when pve-main (and its DHCP server) returned and the interfaces landed back
   on their reserved addresses.
5. Nov 2 (as of ~14:55Z): ai-gpu was rebooted at 14:44Z and its cluster is UP again — but sitting
   on `10.0.99.152`, so anything pinned to `.151` (DNS, firewall rules, scrape targets, certs)
   needs checking. **dev is still DOWN**: it keeps renewing `10.0.77.131` every 5 minutes — even
   after pve-main's 13:51Z boot and even ai-gpu's post-reboot DISCOVER got `.152` — i.e. the DHCP
   responder currently winning on both subnets is NOT the server that holds the `.12`/`.151`
   reservations. Fix dev by restoring the reservation-holding DHCP service (check it came up on
   pve-main after the crash — likely VM 107/120 appliance), then release/renew or reboot dev.

Side observations:
- ai-gpu kubelet logged "Disk usage on image filesystem is over the high threshold" every 5 min
  before the outage — its image filesystem is chronically near-full; worth a cleanup regardless.
- All other clusters (monitoring, proxy-local, gpu, infra, grow, media, home) verified UP at
  14:55Z; grow/home-lab/media journals show the exact 195-min gap (10:40→13:55Z) matching
  pve-main's Nov 2 death, confirming they are its VMs.

## Addendum 2: host-side kernel logs (captured by user on pve-main, Nov 2 ~11:40 MST)

`journalctl --list-boots` + `-k` tails settle the mechanism:

- Boot -1 (Nov 1 05:36:10 → Nov 2 03:34:37 MST) is the session that died in the Nov 2 backup
  window; its end timestamp matches the last Prometheus sample (10:34Z) to the minute. The final
  kernel message is `perf: interrupt took too long` at Nov 1 17:39 MST — then ~10 h of silence and
  death with **no panic, oops, hung_task, RCU stall, MCE, or thermal message**. No auto-reboot
  (dead 3h17m until manual power cycle).
- This rules out the ZFS/-26 deadlock and every soft-hang class (hung-task detector prints at
  120 s; the forum reporter's -26 ZFS deadlock produced full [zfs]/[spl] traces). Verdict:
  **silent hard lockup** — all-CPU wedge (hard lockup / IERR-CATERR) or instant power/thermal
  death, under sustained backup IO.
- Boots -3/-2 (Nov 1 04:54–04:56, 04:59–05:35 MST) are the user's recovery attempts; -2 ends in a
  clean `systemd-shutdown`. The two Oct 31 sessions (update boot 17:59 MST, crash-#1 boot 20:47
  MST) are **missing from list-boots** — journals didn't survive those hard freezes.
- Hardware profile revealed: HP desktop (hp_bioscfg), Coffee Lake, 128 GB non-ECC, NVIDIA GPU on
  vfio-pci (0000:01:00.0/.1) passthrough, WiFi (0000:70:00.0) passthrough, r8152 USB NIC as
  primary LAN on bus 4 shared with StreamCam; Bluetooth firmware download fails in a retry loop
  every boot (-108/-110); Logitech receivers re-enumerate repeatedly; softdog loaded but not
  petting. Chronic xhci/USB reset storm at every boot.
- ZFS final state: `zfs-import@backup.service` (dangling unit for a long-gone pool named
  "backup") disabled by user; `/etc/pve/storage.cfg` has no zfspool entry (leftovers: disabled
  `backup` dir + `pve` lvm entries); pvesm active: local (dir), local-lvm (lvmthin, 79.3% used),
  vms (lvmthin, 74.4% used), removable_1/2 (PBS, backup targets).
- Thin-pool watch item: local-lvm 79.3%, vms 74.4% — 100% would stall all VM IO.

Updated plan: kernel pin (7.0.14-25-pve, fallback 6.17.13-2-pve) is the discriminating experiment
kernel-vs-hardware; if freezes persist on the old kernel → memtest86+, smartctl -x both disks,
cooling/repaste, HP BIOS + microcode update, PSU review. Safety nets: iTCO watchdog via
systemd RuntimeWatchdogSec=60, kdump-tools + crashkernel=256M in /etc/kernel/cmdline +
proxmox-boot-tool refresh, hung_task/softlockup panic sysctls. Trigger reduction: throttle/pause
the 2 AM vzdump job (bwlimit), consider moving vmbr0 from the r8152 USB NIC to the idle onboard
enp0s31f6, BIOS "After Power Loss: Power On".

## Open questions

- Which appliance serves DHCP (with the `.12`/`.151` reservations) for 10.0.77.x/10.0.99.x — VM
  107 (dual-NIC, router-shaped) or VM 120 on pve-main? — and why did a different responder win
  even after pve-main's Nov 2 13:51Z recovery? Until that's fixed, dev stays down and ai-gpu runs
  on an off-reservation address.
- What exactly runs at 2:00 AM MST (and what is VM 120's evening burst job)? Determines whether
  the trigger is vzdump, PBS, or a guest-side sync.
- Did pve-infra's Nov 1 ~5:31 AM drop have the same cause (also -26, also USB-NIC uplink), or was
  it a deliberate reboot during the pve-main recovery?
- Was crash #1 (Oct 31, 8:35 PM) auto-rebooted by panic or power-cycled by hand? The previous-boot
  journal answers this.
