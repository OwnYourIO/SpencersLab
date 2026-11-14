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
`ttm.pages_limit` 29360128 completes the pasted pair — the same number,
twice). That number, not
the stock RAM-minus-formula, is the envelope this note
measures against. This box runs a custom boot-parameter set —
the exact paste strings, verbatim: `amd_iommu=off amdgpu.lockup_timeout=30000
ttm.page_pool_size=29360128 ttm.pages_limit=29360128`. Re-read them on
every receipt; do not assume any of it survived a kernel update by accident.

## 1. LINK — the PCIe speed defect, PROVEN downgraded (first suspect)

Report token (two of the three boots): `link-below-max: … runs 8.0 GT/s x4 of its
16.0 GT/s x4 while the card is 49% busy` — the WARN REPRINTED on the fresh
15:01Z boot, which is what PROVES the downgrade (§D6.6: report-2's silence
was luck/state; the retrain-vs-luck clause is CLOSED). Kernel boot line
verbatim: `31.504 Gb/s available PCIe bandwidth, limited by 8.0 GT/s PCIe
x4 link at 0000:00:03.1 (capable of 512.00 Gb/s-class 504.112 Gb/s with
32.0 GT/s x16)`.

Width vs speed, precisely: the **x4 width is PHYSICAL** here — the root
port's own LnkCap is 16 GT/s **x4** (OCuLink/SFF-8611 carries 4 lanes; the
"capable x16" class refers to the card silicon, unreachable through an x4
port) — and the bridges behind it are **the card's own silicon**: every
Navi part presents an integrated switch pair (`1002:1478` upstream /
`1002:1479` downstream), so `c2:00.0`/`c3:00.0` belong to the R9700, not
the dock — §D6.6's "(switch upstream)" label is RETIRED by §R9/D33. The
DEG1 is Minisforum's PASSIVE Gen4 x4 OCuLink dock (no switch, no retimer),
so exactly ONE physical link negotiates: root port `00:00:03.1` ↔ card,
across the cable and the passive dock PCB. Inside the card the endpoint
side trains `c3:00.0`/`c4:00.0` at 32 GT/s x16, which proves the
downstream is not the limiter. The only defect candidate is the SPEED:
Gen3 where the port caps Gen4. 3.94 GB/s raw ≈ HALF the RQ1-planned
7.0–7.2 GB/s class for this path (RESEARCH RQ1/RQ4 envelope) — which
predicts the ~142 t/s prefill signature, and why LINK is the FIRST suspect:
worth 2–4× prefill, vs the n-gram tier's 3–10% decode band.

The registers, re-read (D38(1)): the old `EqualizationComplete+/Phase1-3+` paste is
the **legacy 8.0 GT/s** EQ status in the base capability's `LnkSta2` — Gen4 owns a
separate extended cap (ID `0x26`, printed as `Phy16Sta`). The card's own read then
settled the premise (§R13): `c2:00.0` prints `Phy16Sta: EquComplete+ EquPhase1+
EquPhase2+ EquPhase3+ LinkEquRequest-` at `[410 v1] Physical Layer 16.0 GT/s` —
Gen4 was TRAINED end-to-end (no re-timer detected ⇒ no link subdivision, §R13-Q1)
and then PARKED at 8. TI's link-training doc (SNLA415, R13-S2) is the mechanism:
EQ is a per-generation cascade and the phases gate on bit-error-rate — Phase 2 at
BER under 10⁻⁴, completion under 10⁻¹² — while on long channels "this level of
signal quality is not possible… repeaters like redrivers and retimers are used"
(generic TI wording, not an inventory of this path); the link settles at "the
fastest rate it can stably support". `LnkSta 8GT/s` beside a completed Gen4 EQ is
therefore SPEC-NORMAL margin behavior, not a mis-configuration: trained-then-parked
(D39). What it kills: "never attempted Gen4" (the card disproves it; there is
no re-driver to blame for that), and D40's host read then retired the last
"host may not have agreed" hedge — BOTH ends completed. What is left is
exactly two things: margin in traffic, or a boot sequence that never ran
the speed change (D40) — Rung 1 tells them apart.

Read toolkit — every rung is witnessed the SAME way, all read-only: the
engine's HARDWARE `link 00:03.1 …` line (startup report) AND `journalctl -k -b
| grep 'available PCIe bandwidth'` as the kernel's second witness — BOTH
**read under load**: idle parks the link at 2.5 GT/s, the trap that fooled
early reads. The honest busy census across the three witness boots is
**49% → 50% → 48%** (§D6.6/§D8/§D10); a "61%" reading NEVER EXISTED in the
ticket's records (D36's self-correction, against our own records first).
Support reads: `sudo lspci -vvv -s 00:00:03.1 | grep -E
'LnkCap:|LnkSta:|LnkCtl2|TargetSpeed'`,
`cat /sys/bus/pci/devices/0000:c2:00.0/current_speed …/current_width`, and
`sudo dmesg | grep -iE 'GT/s|link training|downgraded'`.

Discriminator status: `LnkCtl2` **TargetSpeed** CLOSED the host-BIOS pin
branch by the owner's own read — lspci prints `Target Link Speed: 16GT/s`
while `LnkSta` reads `8GT/s x4` (D34). The root port is INSTRUCTED to train
Gen4 and FALLS BACK — so the question was never a BIOS speed PIN. §R13 left
one open branch — did the HOST end actually agree? — and D40 ANSWERED it by
read: it did (EquComplete+ at the port too), so BOTH ends completed Gen4 EQ
and the link STILL parked at Gen3. The live branch pair is a post-EQ
margin-ABORT in traffic vs a boot-sequence CLAMP that never ran the change,
and the ladder below is re-pointed to the D40 order — one variable per cold
boot, each rung witnessed with the engine `link` line, `LnkSta` AND
`Phy16Sta`, under load, after a cold boot.

CLOSED rungs — receipts kept, so an owner at 3am can see what was TESTED:

- **FALSIFIED — dock-first power ritual (D35, §D10.2).** The owner ran the full
  cold sequence verbatim (everything off, dock on, 10 s, host on) and the
  GENUINELY NEW boot — Node event `Rebooted … boot id
  4d6202d9-14f2-4e7d-b107-1edec278a73d` at 21:34:43Z, old pod SIGTERM
  21:31:24Z, ≈3 m 19 s off-window — REPRINTED the chain still degraded:
  `link 00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2:00.0 8.0 GT/s x4 (max
  32.0 GT/s x16) -> c3:00.0 32.0 GT/s x16 (max 32.0 GT/s x16) -> c4:00.0
  32.0 GT/s x16 (max 32.0 GT/s x16) [read at 48% busy]` plus the same WARN.
  The rate did not move BECAUSE THE LINK DID NOT MOVE. D33's verdict stands
  re-witnessed — the engine doc's "a link stuck one level down clears on
  reboot" advice is WITNESSED-FALSE here. The ORDER is still a safety step (the dock is
  not hot-plug-capable, R10-S4) — obey it on every attempt below; it is no
  longer a candidate.
- **CLOSED TWICE — BIOS / per-slot firmware (D38(2), §R13-Q5).** The board is
  a Framework Desktop on 03.06 — the LATEST published — and NO version ships
  per-slot PCIe content (3.03/3.05/3.06 release notes audited: PD/EC/OPAL,
  RAM/GRUB, AMD-PI/encoder-fix — no slot speed menu anywhere). The GMKtec
  EVO-X3 lead (R9-S17) is an SEO page for a board this lab does not own; the
  boot-hang fix in that same thread came from a KERNEL update. "Firmware"
  stops appearing in this ladder as a CANDIDATE — and even the last
  theoretical re-opening branch is now read shut: the port DOES print
  `Capabilities: [410 v1] Physical Layer 16.0 GT/s` (D40). What survives is
  one narrow "look and report" question, and only if Rung 1's retrain lands
  16 GT/s: whether this BIOS exposes an AMD-CBS-style per-slot speed
  override anyway — the menu is documented sparse (D40), so never assume.
- **RETIRED — the redriver-purchase rung (§R13-Q5, D39).** Not a purchase
  any more: the bay part is an M2-1955-OCU, vendor-described "Built-in PCIe
  ReDriver to extend PCIe Gen4, 16GT/s…" (R13-S4) — not a rung to run: it
  recommended buying hardware this rig already owns; §R12's error,
  acknowledged and RETIRED in §R13-Q5. No R29Q physical-switches anecdote
  survives it either — different part — and ASM1955's exact silicon class
  stays UNVERIFIED (no public datasheet; ASMedia's own taxonomy lists the
  analog redriver family separately, not its retimer lines, R13-S5).
- **CLOSED — the adapter-identity rung.** The owner answered it in one
  sentence: the part is the M2-1955-OCU above. Its invisibility to
  `lspci -t` is expected, not suspicious — an analog redriver is by design
  invisible to the topology; a *retimer* (not our part) is the protocol
  device that splits training so each side initializes separately ("Link
  subdivision", R13-S2/S3), and participating retimers are DETECTED, not
  invisible: our root port reads `Retimer- 2Retimers-` — no detected unit,
  which is exactly the expected signature of a purely analog part in the
  path (R13-Q1(b)). Absence from the topology proves nothing about it.

LIVE LADDER (§R13-Q5 as RE-ORDERED by D40 — Rung 0 is a receipt now, Rung 1
is the test):

- **Rung 0 — host-end reads: EXECUTED, branch CLOSED by read (D40).** The
  corrected commands first — BOTH original mistakes were mine and cost the
  owner a round, so they are named: `sudo lspci -vvv -s 00:00:03.1 | grep -A4
  'Physical Layer 16.0'` (the earlier `sed -n '/…16.0 GT/s/,+4p'` FAILS — the
  pattern itself contains a slash), and `sudo lspci -vvv -s c2:00.0` — `-s`
  wants the bare slot form, not a doubled `0000:` domain prefix. What the
  corrected reads returned (owner's paste, D40): the root port **does**
  implement the 16 GT/s capability — `Capabilities: [410 v1] Physical Layer
  16.0 GT/s` — and prints `Phy16Sta: EquComplete+ EquPhase1- EquPhase2-
  EquPhase3- LinkEquRequest-`, with `LnkCtl2: Target Link Speed: 16GT/s`
  while `LnkSta: Speed 8GT/s, Width x4`; `c2:00.0` holds `EquComplete+
  Phase1+ Phase2+ Phase3+`. **BOTH ends of the external link completed Gen4
  equalization and the link is STILL parked at Gen3** — §R13's "host never
  agreed ⇒ move the socket" branch is CLOSED by read, not by guess. The
  honest asterisk: the root port's phase bits reading '-' alongside
  EquComplete+ is either unimplemented-per-phase reporting (those bits are
  per-implementation, and a downstream port's phases differ from the
  upstream's) or EQ completed by the upstream port while the host skipped
  its own phase evaluation — either way, the port that CONTROLS the speed
  change declares complete, requests no re-EQ, and still negotiated Gen3.
  The field collapses to two live possibilities (D40): a post-EQ
  speed-change ABORT on margin in traffic — spec-normal per TI above — or a
  boot-sequence/firmware CLAMP that never executed the change. Rung 1 is
  the test that separates them. Two corrections ride this receipt:
  **(c1)** `c4:00.0`'s `EquComplete-` is the **card-INTERNAL** `c3→c4` hop
  — it runs Gen5 (32 GT/s per its own `LnkSta`) and the 16 GT/s status is
  simply UNUSED there; it says NOTHING about our external link, and the
  round that asked for it as a suspect was mis-aimed (my error — recorded
  so nobody re-reads it as a finding). **(c2)** `DevSta: CorrErr-
  NonFatalErr- FatalErr- UnsupReq-` is **UNINFORMATIVE, not clean** —
  `_OSC` withholds AER (`platform does not support [SHPCHotplug AER]`) so
  those bits never populate on this box. The AER-INDEPENDENT error reads
  are the per-lane `LnkErrSta` inside the PCIe capability and the bridge
  `SecSta` (all read-only): `sudo lspci -vvv -s 00:00:03.1 | grep -A6
  'LnkErrSta'`, the same on `c2:00.0`, plus `sudo lspci -vvv -s 00:00:03.1 |
  grep -E 'SecSta|DevSta'`.
- **Rung 1 — FORCED RETRAIN / RELEARN (promoted by D40; a WRITE —
  OWNER-EXECUTED; it BLINKS the link).** The only test left that separates
  a boot-sequence clamp from a channel-margin abort, and the reads above
  left no cheaper separator. Prep: scale radiance DOWN first (the runbook's
  owner-executed scale lane — step 3's shape for strata, step 10's for
  radiance), carrying the §D7 law: a hand scale-down survives only until
  that app's NEXT manual sync, so restoring radiance is a DELIBERATE step,
  not a side effect. Then, owner lane:
  `sudo setpci -s 00:00:03.1 CAP_EXP+0x10.w=20:20` (LnkCtl bit 5 = Retrain
  Link, value:mask form — a RE-RUN of training, not a speed override: the
  target already reads 16GT/s, nothing to write) → `sleep 3` → re-read
  `LnkSta` on `00:00:03.1` AND `c2:00.0`, and `Phy16Sta` on both. The
  heavier re-enumeration route lets the port driver narrate the attempt in
  its own words — watch `dmesg -w` while it runs, OWNER-EXECUTED:
  `echo 1 > /sys/bus/pci/devices/0000:00:03.1/remove` then
  `echo 1 > /sys/bus/pci/rescan` (canonical: remove the bridge subtree,
  rescan after). Verdict rule, written as law (D40): **lands 16 GT/s after
  the retrain ⇒ the negotiation is CAPABLE and simply never ran at boot** —
  the question becomes PERSISTENCE: the socket swap (Rung 2), and an
  AMD-CBS-style per-slot PCIe speed option ONLY if this BIOS exposes one —
  the Framework menu is documented sparse, so that is "look and report",
  never "assume"; **still 8 GT/s ⇒ the channel cannot hold Gen4** — and
  the remaining honest answers are the short/known-Good cable (Rung 3),
  the dock bypass (Rung 4), or spending on TP2 — not another BIOS hunt.
- **Rung 2 — M.2 SOCKET SWAP, demoted by D40 (cost ~0, still worth doing).**
  The two M.2 sockets ride DIFFERENT root ports — `00:02.5` hosts the NVMe,
  `00:03.1` the dock chain (§D11.3, D38(4)) — so moving the bay card is a
  free per-port behavior probe (per-port training differences are the
  inference here, not an externally witnessed effect — D38(5) honesty).
  Its ORIGINAL justification (Rung 0's
  host-asymmetry branch) is CLOSED by read, so it rides behind Rung 1 now:
  run it when the retrain lands 16 and persistence is the live question,
  or as a zero-cost side-check. Score `LnkSta` + `Phy16Sta` after a cold
  boot; respect the dock's power order every time — safety only, the
  ritual itself is FALSIFIED as a fix (above).
- **Rung 3 — RESEAT + SHORT known-Good cable (D40 ordering; merged rung):**
  SFF-8611 at BOTH ends until the latch clicks; full 24-pin/AC seating
  (shallow 24-pin is a documented malfunction class, R10-S7); then a short
  (~30 cm class — Martin_Roth's working build, R12-S2) known-Gen4 SFF-8611
  cable — the platform's own counsel is "keep that cable" and the DEG1 is
  "picky about generic cables" (R11-S2); every added mating interface degrades
  signal integrity (LiKenun, R13-S6). With the signature now read as
  trained-then-parked, this is the margin-shrink move, not a lottery ticket.
- **Rung 4 — DOCK BYPASS, the DECISIVE separator (R10-Q3 verbatim logic):**
  card + the SAME cable straight onto the board's own OCuLink port (open
  frame), or the dock + card on a second Gen4 host. Gen4 while bypassed ⇒
  the dock's PCB/power path owns the defect; still Gen3 while bypassed ⇒ the
  host-port ↔ cable ↔ card triple owns it. The dock trains Gen4 in other
  hands (chimolog's 7.07 GB/s 3DMark witness, R10-S8) and the card's class
  is ruled out — other hosts report this card at Gen4 x4 (R10-Q2 (f), §R9).
- **PARKED — Lane Margining, a detour not a rung (§R13-Q1 tool branch).** The
  capability prints (`[450 v1] Lane Margining at the Receiver`) but nobody has
  armed it: `PortCap: Uses Driver-`, `PortSta: MargReady-/MargSoftReady-` —
  arming means device-config WRITES with link-disturb potential, and no
  mainstream Linux tool is evidenced (UNVERIFIED, R13-S1). The free reads +
  relearn answer the question first; do not spend an evening here.
- **The platform census, plainly (§R13-Q3, D38(3), D39).** A Framework Desktop
  has no native OCuLink — the community method is literally "take up one of
  the nvme slots to an oculink adapter" (R13-S6), which is exactly this rig —
  and NO Framework Desktop owner has EVER published a negotiated link speed:
  the in-field photo builds state no rate (R13-S7), and the closest same-model
  build — Frix_Rioux's llama-bench run on this very model at pp 324.8 / tg
  21.1 (R12-S2) — sits inside OUR band. "Others have done this build
  successfully" therefore most likely means "done at Gen3". Our reads can be
  the first published receipt set for this platform — post them either way.
  And if the chain simply cannot hold 16 GT/s, the bandwidth road is the
  second card (TP2) or a switch-dock purchase — not another cable.
- **Terminal fork (only if rungs 1–4 all keep printing `LnkSta 8GT/s x4`
  under load — and D40 puts it plainly: if a retrain cannot hold 16 GT/s,
  the chassis path is Gen3 and the bandwidth money belongs to TP2, not
  another cable):** the chain cannot hold the 16 GT/s eye in traffic — trained
  ≠ stable; TI's "the fastest rate it can stably support" is the epitaph
  (R13-S2). The honest spend then: the SECOND card (TP2 — halves the per-rank
  crossing; §R11-Q5 prices a narrow link at ~54% of prefill lost for
  weights-crossing regimes like ours), or a switch-dock lane (§R11's hardware
  lane; the DEG1 itself is passive with no switch and no retimer, §R9/D33 —
  a purchase is the owner's call, never a repo step) — or accept 3.94 GB/s
  and run the §D8 profile levers at zero cost. The 3.94→7.88 GB/s dream is
  formally dead on this chassis if this branch lands; link-first was still
  the right ordering, and the link's floor is here (R13-Q5).

NOT-fixes — recorded so this checklist never re-lists a dead end as a cure.
§R10-Q4's law verbatim: "Anything that doesn't land LnkSta first is not a
fix, it's hygiene."

- **`pcie_aspm=off` — NOT-FIX for speed.** Field evidence: it produced
  "no change to PCIe link speed" (R10-S9). ASPM L0s/L1 bits showing in
  `LnkCap` are NORMAL — the knob belongs to the stability channel only.
- **`setpci` TargetSpeed / retrain overrides — NOT-FIX (OWNER-lane
  mechanics at most).** The value already reads 16GT/s (D34) — nothing to write —
  writing it anyway is link-down/unbootable risk for zero speed upside; the
  runtime retrain itself showed "no effect" in the field case (R10-S9),
  recorded to STOP pretend-faster attempts. D39's distinction, kept through
  D40's promotion: Rung 1's retrain-BIT write RE-RUNS training — it does not
  override the target; and even a no-effect verdict counts, because what the
  attempt narrates in `dmesg` plus the post-retrain reads ARE the point.
- **STABILITY — due regardless, explicitly NOT a throughput fix.** The
  report STILL prints `runtime pm active (control auto)` after the cold
  cycle (§D10.3) and the root port ships `d3cold_allowed=1` by default:
  the chain is armed, un-pinned, for the D3cold/BOCO "device lost from bus"
  class. The hygiene: a udev rule pinning `d3cold_allowed=0` across the
  chain including `00:00:03.1`, plus the `amdgpu.runpm=0` boot param — the
  ArcheoCodix precedent (R10-S6: GPD Win 4 + the SAME DEG1 + RX 9070 XT,
  same `00:03.1` root port, same 1002:1478/1479 card bridges) landed
  exactly this against bus-loss. On this churn-heavy lane (see HEAT-ENGINE)
  a mid-session power-state drop costs MORE, which is why the row is due
  even while Gen3 persists. Mechanics stay OWNER-EXECUTED — udev file +
  kernel param, then one cold boot and the receipts above; stability, not
  speed.

Any rung's receipt: re-read the engine startup report AND capture
`GET /diagnostics` under a long prefill — the link widths under load are
the receipt; a rung scores ONLY when `LnkSta` reads 16.0 GT/s x4 and the
engine line + `journalctl -k -b` agree — `Phy16Sta: EquComplete+` alone is
NOT the win (BOTH ends print it while the link parks at 8 — D40 is exactly
that receipt).
The payoff model is unchanged: Gen4 x4 buys prefill
249→~450–500 t/s and warm decode toward the ~35 t/s compute floor (§D8).

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

The options are a HIERARCHY, not a menu of equals:
**1 — DEAD at this profile: the RAM tier — `--ngram-placement ram` / a
`ram=DIR` shared table pins 47.68 GiB on top of the 71.04 GiB already
printed: 71.04 + 47.68 = 118.72 > 110 (and > 96) — unlocking MEMLOCK (§2)
BUYS NOTHING HERE, moot by the sum; dropping `--kv-resident` to fund it
forfeits the 8-session lever — a profile negotiation with an owner
sign-off, never a scalar.**
**2 — THE LIVE POSTURE: stay on disk in 4 KiB spans** — today's shape; the
published cost is the ram-vs-disk band 3–10% decode ≈ 0.3–1.2 tok/s at the
fresh 11.2 — second-order against the LINK defect.
**3 — THE OWNER'S STORAGE LANE: move /models to XFS/ext4** so statx reports
alignment and the engine leaves its 4 KiB-span fallback — a host
STORAGE-LANE decision on the SHARED 500Gi claim (it carries
llama.cpp/strata/vllm data too; a chart value cannot express it),
fleet/deferred-card territory. Two arithmetic notes beside the hierarchy:
the tier WORDS overlap — pool 42.70 + mirror ~32 + arena 2.00 + placement
1.18 + staging sums to 77.88 against the printed whole 71.04; price the
BOUNDED 71.04, never a re-added decomposition (D30(2)); and this disk tier
is O_DIRECT — the table never enters page cache (host footprint ~85 MiB
io_uring row cache), so "raise the cgroup limit starves the cache" is
REFUTED (D30(3)). Recommendation: stay on (2); measure (3) only if the
band earns a device move AFTER the link fix. Checks (read-only):
`findmnt -T <pack-path>`, `sudo filefrag -v <pack> | head -20`, the dd
above.

## 4. GOVERNOR — the writes MOST PROBABLY DID NOT PERSIST across the reboot; persistence routes only

Host reads, today: all 32 CPUs `performance`/EPP `performance`, policy
2.00–5.19 GHz (owner's paste §3). Yet the FRESH 15:01Z boot's startup
report printed `note cpu-governor: the CPU governor is powersave with
energy preference balance_performance`. The engine's HARDWARE block is a
boot-time snapshot (RESEARCH RQ3). The reboot events date the fresh
snapshot, so the MOST PROBABLE reading is that the writes did not persist
across the reboot (non-persistence, not mere staleness) — §D6.4's own
adjudication keeps the alternative alive: if the owner wrote
performance AFTER that boot, the report line is simply stale for later
per-CPU changes, and the engine side alone cannot separate the two (no
repo record of the write time exists). A runtime
`cpupower frequency-set` is in either case NOT the fix — that OWNER-EXECUTED
write reverts on the next reboot (there is no repo record of when the owner
set performance; their paste is the only evidence of the write). SECOND
WITNESS (§D10.3): the 21:34:43Z full power cycle — the dock-first ritual boot
(D35) — re-printed `powersave` too; the non-persistence reading survived a
second cold boot, and the persistence routes below stand unchanged.

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
`ttm.page_pool_size=29360128` / `ttm.pages_limit=29360128` — the printed
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

## 14. HEAT-ENGINE — the mover IS engaged and CHURNING: the exit banner settles it

The family's founding reading — `0 dispatches`, resident-per-layer `max 154`,
mover idle, "every expert already fits resident" — is REVISED by the drained
pod's recovered EXIT BANNER (§D10.5, pod `5f7d6b95d7-4fccz`, graceful drain
at the 21:31:24Z SIGTERM): the ticket's first COMPLETE mover receipt — the
armed counters quoted complete below, tail included (the full multi-line
banner with its per-layer tables is EXPLORE §D10.5) — a truncated quote
re-opens the mis-read class the banner closed:

`heat engine: 20678 dispatches, 12129 swaps proposed, 13736 promotions, 11960
demotions; 9993 distinct promoted, 4971 readmits (36% of promotions were of
something already demoted); resident units a layer: min 0 max 300 mean 67.2 sd
94.5; mover: 71.40 GiB h2d, 19.08 GiB d2h; prefetch: 46.2% of copies looked
back on routed; 49 layer-sweeps found nothing new; 328 dispatches declined on
hysteresis; 265 starved of a slab slot, 3721 of a pool slot`

- **READ ARTIFACT:** boot B's literal `0 dispatches` was not a state — the
  mover demonstrably ran on this profile, and the live `expert prefetch
  resting … under the 30% that pays` line (29%/22%/26% across the three
  boots) is the same idle-PREFETCH signature, not engine idleness. §D8's
  "unsettled mover" question is CLOSED.
- **SUPERSEDED:** §D8.2(b)'s inference that `max 154` was the per-layer
  capacity — residency reaches 300 with the documented KV/arena loans (520
  KV-cache slots + 1416 activation-arena slots lendable to the mover;
  ≈37% of the 25078 units resident is the WORKING state), the `L48+ zero`
  rows are the non-MoE layer plane, and D36 records the self-correction.
- **THE CHURN RIDES THE SAME 3.94 GB/s LINK:** re-placement traffic on the
  order of ~90–100 MiB per served token sits ON TOP of the ~200 MiB/token
  miss stream, during exactly the early requests that look worst — which is
  why short generations look catastrophic and long ones recover as the
  miss-fraction converges (m 0.29 → 0.20 → ~0.17 on §D8's 3.8× warm-up
  curve; the banner's settled state is `49 layer-sweeps found nothing new`).
  The post-ritual prints — `11.0 tok/s` at gen 1047, `16.4` at gen 1707 —
  are the SAME, MID-RAMP, NOT a regression: "same or worse" adjudicates to
  "same" (D36). Link-first SURVIVES STRENGTHENED: one Gen4 fix halves the
  misses AND the churn AND the wasted prefetch together.
- **Fair measurement, both still owed:** no settled number exists — the
  fixed ≥2000-token probe at request-position ≥4 (§D8.3) has NEVER been run
  and the runbook's step-6 8-session gate is still unrun (owner-lane, each
  read-only). Standing law: **the receipt decides, never the rate** (§R8).
  Recorded, NO advice shipped: 36% readmits + 46.2% no-lookback prefetch MAY
  say the heat.h guards are off-optimum on this profile — UNVERIFIED (D36).
- Unchanged watch item: if demotion BURSTS coincide with RAM spikes, the
  pinned-burst class (RESEARCH RQ1's Wilde note) is the thing to watch — it
  rides the same arithmetic discussed at §3, not a host knob.

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
  C12 1000m cap is ÷5 of that ⇒ ~5.8–13.6 min (one core is the whole gain,
  D30(6); the drafted 8–23 was §D4.4's un-quoted full-feed-disk
  counterfactual, not a cap-bound figure); the hash restarts at byte 0 on
  any pod
  loss, so never touch a pod mid-hash. The marker now exists: every
  restart is the <1 s skip. The host-side hash-and-touch loop-breaker
  (§D3b.6 era) remains human-owned, host lane, and is NOT a substitute for
  the shipped chart value.
