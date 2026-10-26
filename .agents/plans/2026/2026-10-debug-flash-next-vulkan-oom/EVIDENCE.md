# EVIDENCE — C01: zero-repro mechanism proof + the six must-measure items

ticket: 2026/2026-10-debug-flash-next-vulkan-oom · chunk: C01 · run-tag: openrouter-qwen3-8-flash
branch: debug-flash-next-vulkan-oom-openrouter-qwen3-8-flash
written: 2026-10-26T14:40:00Z (agent-dev). Nothing here was obtained by an agent-run pod-exec; host/pod
shell material is operator-run output pasted into the pipeline session or is listed in §9 as awaiting.

Source tags used throughout (provenance discipline, AC7):
- `[MCP]` readonly-ai-gpu-kubernetes tool call (2026-10-26T14:0x–14:1xZ unless noted)
- `[HTTP]` GET against https://llama.spencerslab.com (public llama-swap ingress, live 2026-10-26)
- `[PROM]` query_prometheus via readonly-global-grafana (datasource `prometheus`, healthy; instance ai-gpu node-exporter)
- `[GGUF]` HF API + HTTP Range prefix fetch of unsloth/Qwen3.8-Flash-Next-GGUF headers, parsed with the vendored `GGML_QUANT_SIZES` (charts/llama-swap/scripts/gguf-py) — method precedent: charts/llama-swap/values.yaml flash-next block (C04-era)
- `[GHCR]` registry blob forensics of the exact image digest the pod reports [MCP]
- `[API]` api.github.com / raw GitHub repo lookups (FRICTION-resolved egress path)
- `[CONFIGMAP]` resources_get on live ConfigMaps in gpu-ai ns/default
- `[USER]` operator-run host command, pasted 2026-10-26 ~14:20Z (ssh root@gpu-ai.spencerslab.com, node ai-gpu, shell TZ = MDT = UTC−6)
- `[LOG]` llama-swap per-model log buffer replay (`GET /logs/stream/<model_id>`, history)

Status of the chunk's Loki path: the Loki datasource is DOWN (loki-read 0/1, backend 132 restarts
[MCP monitoring cluster, 2026-10-26T14:02Z]; Grafana→Loki returns 502/"Unable to connect").
Additionally established below (§6/§8): upstream llama-server logs never reach Loki at all on this
box, so the Loki leg of C01's plan was methodologically void even when healthy. No evidence here
depends on Loki.

## 1. Crash-window timeline + full upstream log (chunk task 17)

Wall-clock timeline for the most recent `qwen3.8-flash-next-q3` load attempt (the one whose buffer is
still on the box — zero-repro):

| time (UTC) | event | source |
|---|---|---|
| 2026-10-26T01:18:28 | node ai-gpu boot (kernel 7.3.0-1-default, `#1 SMP PREEMPT_DYNAMIC Mon Oct 19 15:21:44 UTC 2026`) | [PROM] node_boot_time_seconds 1792977508; [USER] `journalctl -k -b 0` first lines local `Oct 25 19:18:32` (= 01:18:32Z) |
| 2026-10-26T03:29:23 | pod `gpu-ai-llama-swap-5bd86f5995-dwwcr` created (rollout; template hash f8d4958d7 → 5bd86f5995) | [MCP] pods_get |
| 2026-10-26T03:29:38 | main container started (`ghcr.io/mostlygeek/llama-swap:unified-vulkan-266`, imageID sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045); `/api/hardware` captured_at 03:29:38.165Z | [MCP]; [HTTP] GET /api/hardware |
| 2026-10-26T03:29:39 | pod Ready 2/2 | [MCP] |
| ≈ 2026-10-26T03:30:31 | flash-next-q3 upstream (llama-server) launched — attempt began | derived: kernel device-lost flood start 03:30:52 − buffer-relative 20.9 s (§2) |
| 2026-10-26T03:30:52–53 | kernel: `amdgpu 0000:c2:00.0: [drm] *ERROR* amdgpu_vm_validate() failed.` + `*ERROR* Not enough memory for command submission!` — 1772 journal lines in the queried window | [USER] `journalctl -k --since "2026-10-26T03:25:00Z" --until "2026-10-26T03:45:00Z" \| grep -E "amdgpu_vm_validate\|BO_VA\|command submission\|ring .* timeout"` (paste truncated at 511 lines; representative pair quoted verbatim below) |
| 2026-10-26T14:06–14:07 | C01 evidence capture: full crash-session buffer replayed (924 bytes, static across two 25–30 s reads) | [LOG] |

Kernel pair verbatim (the RESEARCH §1.1 "kernel twin lines" signature — mechanism's kernel side, on-box):

```
Oct 25 21:30:52 ai-gpu kernel: amdgpu 0000:c2:00.0: [drm] *ERROR* amdgpu_vm_validate() failed.
Oct 25 21:30:52 ai-gpu kernel: amdgpu 0000:c2:00.0: [drm] *ERROR* Not enough memory for command submission!
```
(node-local MDT timestamps; 21:30:52 local = 03:30:52 UTC.)

No `BO_VA` and no `ring .* timeout` lines matched in the window — the MiniMax `Couldn't update BO_VA (-12)`
variant [23] and the ring-timeout DeviceLost class [36][20] are absent from this crash's kernel record.

## 2. Zero-repro check: the `load_tensors:` buffer split (AC1)

**Verdict: the historical crash log does NOT contain the `load_tensors:` buffer-split summary — the
load aborted mid-`load_tensors` (device-lost at +20.9 s), before the split is printed.** The split
comes free with C04's one consented attempt (planned regime); no attempt was burned here.

Full retained upstream session (924 B, relative timestamps `s.mmm`-style as emitted; verbatim [LOG]
GET `https://llama.spencerslab.com/logs/stream/qwen3.8-flash-next-q3`, 2026-10-26T14:06:52Z):

> 0.00.027.508 I srv  llama_server: initializing ...
> 0.00.386.152 I cmn  common_param: common_params_print_info: verbosity = 3 (adjust with the `-lv N` CLI arg)
> 0.00.386.433 W srv  llama_server: security: no API key is set and CORS allows all origins (see https://github.com/ggml-org/llama.cpp/pull/25655)
> 0.00.390.699 I srv    load_model: loading model 'unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL'
> 0.18.522.277 W resolve_fused_ops: layer 3 is assigned to device Vulkan0 but fused top-k mask is assigned to device CPU (usually due to missing support)
> 0.18.522.281 W resolve_fused_ops: fused top-k mask not supported, set to disabled
> 0.19.706.874 I cmn          init: llama threadpool init, n_threads = 10
> radv/amdgpu: Not enough memory for command submission.
> 0.20.915.256 E ggml_vulkan: device lost on Vulkan0
> terminate called after throwing an instance of 'vk::DeviceLostError'
>   what():  vk::Queue::submit: ErrorDeviceLost

Mechanism fingerprint on-box: `radv/amdgpu: Not enough memory for command submission.` immediately
followed by `device lost on Vulkan0`, mid-load (no `model loaded` line, no `load_tensors: Vulkan0
model buffer` summary) — identical failure mode to upstream #30987's GTT OOM [35].

Buffer-class reference (upstream #30987 log for the same model family under the same pinned regime,
NOT this box — quoted for fingerprint context, RESEARCH §4.1 [35]):
`Vulkan0 model buffer 21184 MiB / Vulkan_Host model buffer 40681 MiB / CPU_Mapped model buffer 27465 MiB`.
Note the CPU_Mapped figure ≈ 27465 MiB sits right at this file's measured PLE tensor of 27,472 MiB
(28,800,138,240 B = 26.82 GiB = 27,472 MiB, §5) — the `>4 GiB host-forced tensor` fingerprint.

The split numbers that WILL distinguish `Vulkan_Host` (GTT-pinned) from `CPU_Mapped` (reclaimable
mmap) for qwen3.8-flash-next-q3 on this box are produced by C04's attempt under branch A.
Fused top-k warning: present at rel 0.18.5, recorded only (confirmed perf-only red herring —
RESEARCH §2.2).

## 3. GTT budget and the required-vs-budget gate table (AC2 — C03's A vs A+B fork)

Boot-line measurement [USER 2026-10-26, `journalctl -k -b 0 | grep -E "of (VRAM|GTT) memory ready"`]:

```
Oct 25 19:18:32 ai-gpu kernel: amdgpu 0000:c2:00.0:  512M of VRAM memory ready
Oct 25 19:18:32 ai-gpu kernel: amdgpu 0000:c2:00.0:  64038M of GTT memory ready.
```

Normalized: **measured GTT budget = 64038 MiB of GTT memory ready ≈ 62.54 GiB** (512 MiB VRAM
carve-out separate). Sysfs confirms the sizing:

| item | value | source |
|---|---|---|
| /sys/module/ttm/parameters/pages_limit | `16393935` pages × 4 KiB = 67,149,557,760 B = 64038.81 MiB | [USER cat /sys/module/ttm/parameters/pages_limit] |
| /sys/module/amdgpu/parameters/gttsize | `-1` (deprecated default → TTM sizes GTT) | [USER cat /sys/module/amdgpu/parameters/gttsize] |
| node MemTotal | 134,299,119,616 B = 125.07 GiB | [PROM] node_memory_MemTotal_bytes{cluster="gpu-ai"} 2026-10-26T14:08:15Z |

Arithmetic settling RESEARCH contradiction #7: MemTotal/2 = 64,038.81 MiB — the printed GTT budget is
**exactly half of MemTotal**. Kernel 7.3.0-1 does NOT size GTT "more generously"; the classic ½-RAM
default holds [15][17]. `/api/hardware`'s 512 MiB "dedicated" (536,870,912 B) is the BIOS UMA
carve-out only, as the plan suspected [HTTP GET /api/hardware 2026-10-26T14:03Z].

### Required-GTT vs measured-budget table (the C03 gate deliverable)

Demand side from §5's tensor dump (exact GGUF byte sums), arch constants from RESEARCH §Q2.1
(48 layers, 12 full-attention layers, 2 KV heads × 256 head-dim from `attn_k [2560,512]` /
`attn_q [2560,12288]`), config constants from §8 (`-c 262144 -np 1`, q8_0 KV, 1 B/elem).

| regime | GTT / device demand (weights-pinned) | KV | compute buffers | draft/MTP | total vs budget 64038 MiB | outcome |
|---|---|---|---|---|---|---|
| **current: `--load-mode none` + `-ot experts=CPU`** (crashed) | experts 55,823,564,800 B = 51.99 GiB (Vulkan_Host pinned) + dense 4.75 GiB + draft exps 2.49 GiB | 3.0 GiB (12×2×256×2×262144 B) | ~2–5 GiB (estimate) | 3.85 GiB sidecar loaded | **62.2–67.2 GiB vs 62.54 GiB** | at/over budget → ENOMEM mid-load ✓ matches §1–§2 |
| **branch A first cut: `--load-mode mmap --fit off`, MTP off** | ≈0 GiB pinned (experts → CPU_Mapped file-backed reclaimable; PLE stays CPU_Mapped 26.82 GiB, reclaimable page cache) | 3.0 GiB device | ~2–5 GiB device | 0 (draft removed first cut) | **device/GTT ≈ 10–13 GiB** (RESEARCH §4.3 conservative worst case 25–30 GiB) | ≥ 32–50 GiB headroom under the 62.54 GiB budget |

**Gate verdict (C03, A vs A+B): branch A alone — the measured 64038 MiB GTT budget comfortably holds
the mmap-regime device demand; branch B (`ttm.pages_limit=32505856`) is NOT required and is not
triggered.** (Per DECISIONS 2026-10-26: if branch A provably fails after the escalation ladder, B
comes back to the user as a pre-authorized host change decision — C01's measurement resolves
coord's decision-point 2 to "not needed now".)

## 4. lockup_timeout (AC3)

Measured value: `lockup_timeout = 30000` (ms) — [USER 2026-10-26 ~14:20Z,
`cat /sys/module/amdgpu/parameters/lockup_timeout`].

- Settles RESEARCH contradiction #1 for this box: the node runs an explicit 30000 ms — consistent
  with the 2026-10-13 `amdgpu.lockup_timeout=30000` boot-parameter precedent noted in the chunk.
  (Raw default hypotheses 2000/10000/60000 [19][16][18][20][21] all excluded; the exact
  `/proc/cmdline` confirmation line is §9 item 7, awaiting user — the sysfs read alone is the
  operative value.)
- Decision rule honored: **recorded only; no change** was made — single-node k3s box, raising it
  further is an accepted system-hang risk [21][20] and irrelevant to the load-time (GTT) crash class.

## 5. GGUF tensor dumps (AC5) — UD-Q3_K_XL names + MTP hc-layout

Method: HF API `?blobs=true` sibling sizes + HTTP Range prefix fetches (`bytes=0-25165823`,
HTTP 206) of the header/tensor-info sections; parsed with a stdlib struct reader against the
vendored `GGML_QUANT_SIZES` table (charts/llama-swap/scripts/gguf-py/gguf/constants.py — used,
not modified). Two method findings recorded for C03/C04 reuse:
(a) the vendored `GGUFReader` eagerly materialises tensor data and cannot parse a truncated
prefix; (b) unsloth's multi-split writer appends a 2-byte field after each tensor-info `offset`
(401/401 entries observed) — standard packed-entry readers desync after the first entry.

Repo `unsloth/Qwen3.8-Flash-Next-GGUF` [GGUF+HTTP 2026-10-26T14:15–14:25Z]:
- `UD-Q3_K_XL/Qwen3.8-Flash-Next-UD-Q3_K_XL-00001-of-00003.gguf` — metadata-only primary
  (10,946,624 B; `n_tensors=0`; `split.count=3`, `split.tensors.count=1224`,
  `general.architecture=qwen4exp`, `general.file_type=12`).
- shard 00002: 46.55 GiB (402 tensors incl. the PLE); shard 00003: 37.25 GiB (822 tensors).
- **Shard total = 89,986,353,824 B = 83.81 GiB — matches the catalog figure 83.8 GiB (c)** (sum of
  tensor-info sizes: 83.80 GiB; the 0.01 GiB delta is shard padding).

| check | verdict | evidence |
|---|---|---|
| (a) `-ot "\.ffn_.*_exps\.=CPU"` regex effectiveness | **MATCHED: 144 / 1224 tensors** — the per-layer fused `blk.N.ffn_{gate,up,down}_exps.weight` × 48 layers; sum 55,823,564,800 B = 51.99 GiB. Reproduced live (C04-era 144/147 claim confirmed at name level) | [GGUF] tensor-info scan, regex `\.ffn_.*_exps\.` |
| (b) PLE tensor | **`per_layer_token_embd.weight`: dims [160, 320001536], type 20 = IQ4_NL, 51,200,245,760 elems = 28,800,138,240 B = 26.82 GiB** — single tensor, exceeds the gfx1151 4 GiB `maxStorageBufferRange` cap → host-forced placement regardless of `-ot` [41][42] | [GGUF] shard-00002 tensor-info |
| (c) size vs catalog | 83.81 GiB ≈ 83.8 GiB ✓ | [GGUF] |
| (d) shared experts | `_shexp` tensors: 192, total 0.23 GiB — stay GPU-resident as intended | [GGUF] |
| dense remainder | 887 tensors = 4.75 GiB (attn/embed/output/hc/etc.) | [GGUF] |

**MTP sidecar hc-layout verdict — POST-#28901, gate 2 NOT blocked:**
File `mtp-Qwen3.8-Flash-Next-Q8_0.gguf` (repo root, 3.85 GiB; an identical copy exists under
`MTP/`) contains 34 tensors, including the full hc family:
`blk.48.hc_attn_{down,inject,norm,up}.weight`, `blk.48.hc_ffn_{down,inject,norm,up}.weight`,
`blk.48.nextn.{enorm,hnorm,eh_proj}.weight`, `blk.48.nextn.hc_head_{down,norm,up}.weight`,
plus `blk.48.ffn_*_exps.weight` (2.49 GiB) — a pre-#28901 sidecar would lack the `hc_*`/`nextn.hc_head_*`
tensors entirely and die at load with `check_tensor_dims`.
The exact marker name `output_hc_norm.weight` **found — in the MAIN model** (shard-00002 tensor-info
lists `output_hc_down.weight`, `output_hc_norm.weight`, `output_hc_up.weight`): it is an output-head
tensor of the base file, not of the draft sidecar — the b11810 `check_tensor_dims: 'output_hc_norm.weight'
not found` failure [54][55] is a MAIN-GGUF check, and our UD-Q3_K_XL primary carries it. Combined
with the sidecar's post-#28901 hc layout, the hc-layout gate for C04's MTP re-add **passes**.
(Remaining MTP-off-for-first-load rule stands for the separate #27306 runtime DeviceLost class —
DECISIONS two-gate path, layout was gate 1.)

## 6. Working-regime comparison: `qwen3.6-35b-a3b-q8` (chunk task 18)

**Planned Loki retrieval is methodologically void on this box, established by pipeline forensics:**
- gpu-ai's Alloy logs pipeline contains only `loki.source.journal "worker"` (node journald) and
  `loki.source.file "pod_logs"` (container stdout) [CONFIGMAP gpu-ai-k8s-monitoring-alloy-logs].
- llama-swap runs with `logToStdout: proxy,http` [CONFIGMAP llama-swap-config] — upstream
  llama-server logs (which carry the `load_tensors` lines) are NOT shipped to stdout, hence were
  never in Loki. (Independent of the current loki-read outage, §Status.)
- The q8 rung's upstream session ended with pod instance f8d4958d7; its in-memory buffer died with
  the process. The old pod's retained stdout greps to zero `load_tensors|Vulkan_Host` lines
  (8 KiB, rotated proxy noise) [MCP pods_log gpu-ai-llama-swap-f8d4958d7-m27vw].

**Substitute live evidence of the same size-cliff, same-mechanism claim [35]:** the currently
ready rung `qwen3.8-27b-q6` runs under the SAME pinned regime family — expanded cmd contains
`--load-mode none` + `--spec-type draft-mtp` (its ggml-org Q8_0 MTP draft loaded fine) [HTTP
GET /running 2026-10-26T14:04Z] — 17.5 GiB-class weights ⇒ pinned-GTT demand well inside 62.54
GiB, loads and serves. The 35B-q8 uses `${moe}` (`-ngl 99 -ot … --load-mode none`) and per
RESEARCH §4.1 stays under the same budget. The buffer-split numbers for a working rung will be
captured at C04 (read `/logs/stream/<id>` immediately after the consented load — free).

## 7. Host context snapshot (chunk task 19)

| item | value | source |
|---|---|---|
| node | ai-gpu, openSUSE Tumbleweed, k3s v1.36.5+k3s1, Internal-IP 10.0.99.151, Ready, control-plane | [MCP] resources_list Node 14:01Z |
| kernel | 7.3.0-1-default (`#1 SMP PREEMPT_DYNAMIC Mon Oct 19 15:21:44 UTC 2026`) | [PROM] node_uname_info; [MCP] |
| boot | 2026-10-26T01:18:28Z | [PROM] node_boot_time_seconds |
| MemTotal | 134,299,119,616 B (125.07 GiB) — the `free -h` "total" equivalent | [PROM] node_memory_MemTotal_bytes 14:08:15Z |
| MemAvailable @capture | 78,094,831,616 B (72.73 GiB) — while 27b-q6 + its mmap'd PLE resident | [PROM] node_memory_MemAvailable_bytes 14:08:15Z |
| pod-observed RAM | 136,678,019,072 B (127.3 GiB nominal); OS "ubuntu 24.04, kernel 7.3.0-1-default" (container sees host kernel) | [HTTP] /api/hardware |
| GPU0 (dGPU, out of scope) | AMD, amdgpu driver 7.3.0-1-default | [HTTP] /api/hardware |
| GPU1 (iGPU) | AMD gfx1151, dedicated 536,870,912 B = 512 MiB BIOS carve-out (NOT the budget — see §3) | [HTTP] /api/hardware |
| gpu resource | pod limits/requests `amd.com/gpu: 1`, resourceID 0000:c2:00.0 (device matches the kernel journal PCI id) | [MCP] pods_get |
| free -h / /proc/cmdline / mem_info_* | **awaiting-user** — exact commands in §9 items 6–8; the GTT gate does not depend on them (budget settled by §3 boot line + pages_limit equality) | — |

## 8. Additional on-box findings relevant to C03

1. **`--fit` is not injected**: zero occurrences of `--fit` in the live ConfigMap config.yaml
   (macros + all model cmds grepped) [CONFIGMAP llama-swap-config, fetched 14:05Z]. llama.cpp's
   default applies = fit **on** → RESEARCH §4.2(c)'s dry-load GTT churn + mis-accounting was active
   in the crashed regime. RESEARCH open-q 5 closed. C03's `--fit off` addition is therefore
   behavioral, not cosmetic.
2. Live flash-next-q3 cmd (expanded from macros `${server-cmd} ${threads} ${moe} ${ctx-256k}
   ${flash-and-q8} ${q38-sampling} ${q38-think}`): `llama-server --port … -hf
   unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL -hfd …:mtp-Qwen3.8-Flash-Next-Q8_0 -t 10 -ngl 99 -ot
   "\.ffn_.*_exps\.=CPU" --load-mode none --ctx-size 262144 -b 2048 -ub 2048 --flash-attn on
   --cache-type-k q8_0 --cache-type-v q8_0 … --spec-type draft-mtp --spec-draft-n-max 2` —
   confirms the pinned regime + draft on the live box [CONFIGMAP].
3. Detector-version oddity (`v265` reported by image `unified-vulkan-266`) — RESOLVED, cosmetic:
   the image's own `/versions.txt` (read from the exact running digest, §9 item 9 forensics) embeds
   `llama-swap: 265` with `build_timestamp: 2026-10-22T06:14:27Z`, and the manifest config `created`
   is 2026-10-22T06:14:27.348Z [GHCR]. The tag number is the CI tag sequence; the app version string
   is 265. No separate ticket needed; plan's "Out of scope" note discharged.
4. Upstream logs visibility gap: with `logToStdout: proxy,http`, C04's evidence capture MUST read
   `GET /logs/stream/<model_id>` while the process' buffer still lives (i.e., immediately at the
   load, before further sessions roll it) — C04's procedure artifact (`evidence/c04_verification_procedure.yaml`)
   already specifies per-model buffer reads; this chunk confirms why it's the only channel.

## 9. User-run command list (repo rule: no agent pod-exec — presented, never executed by agents)

Run by the operator 2026-10-26 ~14:20Z on ai-gpu (`ssh root@gpu-ai.spencerslab.com`), outputs quoted
above with node-local timestamps noted:

1. `journalctl -k -b 0 | grep -E "of (VRAM|GTT) memory ready"` — ✅ §3
2. `cat /sys/module/ttm/parameters/pages_limit` — ✅ §3
3. `cat /sys/module/amdgpu/parameters/gttsize` — ✅ §3
4. `cat /sys/module/amdgpu/parameters/lockup_timeout` — ✅ §4
5. `journalctl -k --since "2026-10-26T03:25:00Z" --until "2026-10-26T03:45:00Z" | grep -E "amdgpu_vm_validate|BO_VA|command submission|ring .* timeout"` — ✅ §1 (1772 lines; paste carried 511)

Awaiting user (evidence rows above marked; none gate C03's branch-A verdict):

6. `free -h` — convenience mirror of the [PROM] snapshot
7. `cat /proc/cmdline` — confirm the `amdgpu.lockup_timeout=30000` boot param behind §4's sysfs read
8. `cat /sys/class/drm/card*/device/mem_info_vram_total /sys/class/drm/card*/device/mem_info_gtt_total` (+ `_used` variants) — sysfs mirror of §3's budget (expected: 536870912 / 67149557760 B on the gfx1151 card)
9. `kubectl exec -n default deploy/gpu-ai-llama-swap -c main -- cat /versions.txt` — optional live-pod
   confirmation; the identical file was already read from the running image digest via registry forensics:
   ```
   llama.cpp: e3797b184d428c7a019362612b76971f60af6670
   whisper.cpp: 231638a0717b7822784297e5980965ffcec05810
   stable-diffusion.cpp: a77d3623180b2bc1886f3dd04c0aa04156a987ef
   ik_llama.cpp: 15e7ecacddd87455f3fbc4805bc0508df01fa8cc
   audio.cpp: fb129222ca6f7c7b066c8c70bc99ecd9c6330e8f
   llama-swap: 265
   backend: vulkan
   build_timestamp: 2026-10-22T06:14:27Z
   ```
   (`/versions.txt` content [GHCR] blob sha256:e7666509… of imageID sha256:0cc42f10… — the pod's own image,
   not the host's)
10. `kubectl exec -n default deploy/gpu-ai-llama-swap -c main -- ls /usr/local/bin | grep ik-` — live
    confirmation; established forensically [GHCR] layer sha256:63352f35… contains `usr/local/bin/ik-llama-server`
11. `kubectl exec -n default deploy/gpu-ai-llama-swap -c main -- ik-llama-server --version` — commit/banner echo

## 10. Pod Mesa / ik-llama / llama.cpp versions (AC4 + AC6)

All from the image the pod is actually running (imageID digest forensics [GHCR], 14:30–14:36Z), NOT
the host and NOT guessed:

- **Mesa (bundled in the pod image): 25.2.8** — package `mesa-vulkan-drivers = 25.2.8-0ubuntu0.24.04.4`
  per the dpkg status shipped in the image's apt layer (blob sha256:d8d34d38…); `libvulkan1 = 1.3.275.0-1build1`;
  base OS ubuntu 24.04 (matches /api/hardware `operating_system`). The pod ships its own Mesa [44];
  community repros span 25.2.8–26.2.5 with identical GTT behavior [23][35][47] — our Mesa is the
  floor of that range.
- **llama.cpp: e3797b184d428c7a019362612b76971f60af6670 — verified equal to GitHub release b11810's
  target commit** (published 2026-10-22T07:49:03Z) [API repos/ggml-org/llama.cpp/releases/tags/b11810].
  The image is exactly the build the plan's flag-audit reference names — RESEARCH §3.1's "unfixed at
  b11810" applies verbatim to this box.
- **ik-llama-server: PRESENT** — binary `usr/local/bin/ik-llama-server` in image layer blob
  sha256:63352f35… [GHCR]. **Version/commit: ik_llama.cpp `15e7ecacddd87455f3fbc4805bc0508df01fa8cc`,
  authored 2026-10-21T08:17:06Z** ("Use F32 precision for the indexer top_k computation on CUDA
  (#2712)") [API repos/ikawrakow/ik_llama.cpp/commits/…].
- **qwen4exp support note (C1 gate): the bundled ik commit POST-dates ik PR #2369**
  ("qwen4exp: MTP (NextN) self-speculative decoding support", merged 2026-09-02T16:49:42Z
  [API repos/ikawrakow/ik_llama.cpp/pulls/2369]) by ~7 weeks → the presence gate for C03's C1 rung
  is SATISFIED (verdict: present, gate-passing; RESEARCH [4] still rates ik on this chip low-confidence —
  C1 remains a cheap rung test, not a known win).
- llama-swap: `265` embedded (`tmp/llama-swap-version` blob = "265") under tag `unified-vulkan-266`
  (§8.3).

## 11. Verdict summary — one line per must-measure item (C03's inputs)

1. Zero-repro buffer split: **absent from the historical log by design (abort precedes the print);
   mechanism still proven on-box** (radv ENOMEM + device-lost mid-load + kernel `amdgpu_vm_validate()`
   twin pair, 1772 lines) — no attempt burned; split arrives with C04.
2. GTT budget: **measured 64038 MiB (62.54 GiB) = exactly MemTotal/2; A-alone verdict in §3** → C03
   branch A without B.
3. lockup_timeout: **30000 ms recorded, no change** (§4).
4. ik-llama-server in `-266`: **present**, commit 2026-10-21 > PR #2369 → C1 gate open (§10).
5. Tensor names: **`-ot` regex effective (144/1224, 51.99 GiB)**; PLE 26.82 GiB host-forced; total
   83.81 GiB ✓ (§5).
6. MTP hc-layout: **post-#28901 — gate 2 NOT blocked** (sidecar hc family complete; main carries
   `output_hc_norm.weight`) (§5).
7. Mesa in pod: **25.2.8** (§10). Working-rung Loki comparison: **void method (upstream logs never
   shipped) — substituted by live 27b-q6 same-regime ready** (§6).

## 12. Provenance appendix

All agent reads were readonly: MCP `readonly-ai-gpu-kubernetes` (pods/nodes/configmaps/pods_log),
`readonly-monitoring-kubernetes` (pod health), `readonly-global-grafana` (datasource health,
prometheus queries; loki attempts returned 502/"Unable to connect" 2026-10-26T14:02–14:30Z),
public HTTPS to `llama.spencerslab.com` (health, api/hardware, running, logs, logs/stream),
`ghcr.io` registry API (anonymous pull token), `huggingface.co` API + resolve (Range 206),
`api.github.com`. Capture session: 2026-10-26T14:01–14:36Z. Ephemeral raw captures kept under
/tmp/opencode (gguf_final.out, fnq3_full.txt, apt-layer dpkg status) — quoted inline here, not
tracked in the repo. No cluster mutation, no config edit, no load attempt, no agent-run kubectl exec.

## 13. C04 post-fix record — the mmap regime verified live (agent-dev, 2026-10-26T22:30Z+)

ticket: 2026/2026-10-debug-flash-next-vulkan-oom · chunk: C04 · branch: debug-flash-next-vulkan-oom-openrouter-qwen3-8-flash
Source tags as in §1-12 ([MCP]/[HTTP]/[PROM]/[CONFIGMAP]/[LOG]); new tag `[SSE]` = per-model buffer
replay fetched through the llama-swap UI's same-origin channel via the playwright MCP (the only
agent-reachable route to `GET /logs/stream/<id>` — the sandbox egress proxy buffers long-open
streams and times them out; plain GETs are unaffected). All cluster reads readonly; no admin MCP;
no kubectl apply; no pod/host exec by the agent; kernel params untouched (§13.4).

### 13.1 Landed + synced precheck (procedure step `argocd-sync-check`)

- ArgoCD on gpu-ai: all 8 Applications incl. `gpu-ai` and `gpu-ai-llama-swap` — **Synced / Healthy** [MCP resources_list argoproj.io/v1alpha1 Application].
- Live ConfigMap `llama-swap-config`: `--load-mode mmap` ×5 and `--fit off` ×5 — exactly the five flash-next-family rungs; `--load-mode none` remains only on the untouched `${moe}` rungs (7 occurrences) [CONFIGMAP 21:5xZ]. Matches the C03 render contract byte-for-byte on the flag surface.
- Pod `gpu-ai-llama-swap-fc6d7c8fc-2jmkl` on node ai-gpu: image pin `unified-vulkan-266` unchanged, started **16:14:35Z** via reloader on ConfigMap hash `aef19b7f8233…` [MCP pods_get] — the merged branch rolled out with **0 restarts** since.

### 13.2 Load-attempt record — AC1 (flash-next-q3 reached running; regime applied; one agent attempt, no retries)

| load | trigger (xff) | matrix event | Health check passed | load time | verdict |
|---|---|---|---|---|---|
| A | operator (UI) | 16:15:50Z | 16:16:21Z | 24.55 s (buffer rel) | model loaded, listening :10047 [LOG-proxy + SSE] |
| B | operator | 21:28:18Z | 21:28:37Z | 19.22 s | loaded; served; clean TTL-300s unload 21:34:33Z [LOG-proxy] |
| C | operator | 21:46:33Z | 21:46:48Z | 13.33 s | loaded; 14 min heavy use (§13.6 prefills); clean TTL exit 22:00:5xZ [SSE] |
| D (agent consented attempt) | agent POST /v1/chat/completions (tiny prompt, stream) | 22:20:37Z | 22:21:04Z | 26.66 s | loaded within healthCheckTimeout; evicted 0.6 s post-health by a matrix/preload race (§13.7) before the agent request was forwarded |

Regime actually applied at load — every one of the four sessions prints, ~0.2 s after `loading model
'unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL'`:

> `0.00.4xx W llama_model_loader: tensor overrides to CPU are used with mmap enabled - consider using --load-mode none for better performance` [SSE]

— a warning that exists **only** when the `-ot` CPU overrides and mmap placement are simultaneously
active; absent from the §2 crash session (pinned regime) and from all `-ot`-less rungs. The expanded
runtime cmd of the live rung (`GET /running`, 21:56Z [HTTP]) carries `-ngl 99`,
`-ot "\.ffn_.*_exps\.=CPU"`, `--load-mode mmap`, `--fit off` and **no `--spec-type`/`-hfd` flags** —
the first cut exactly as rendered. MTP absence is also proven positively at load: no
`common_speculative_init_result: loading draft model` line in any flash-next session, while the
healthy 27b-q4 rung's buffer prints exactly that line on the same box [SSE].

Method finding: `load_tensors:` buffer-split INFO lines never reach the per-model buffer on this box
at runtime verbosity 3 — verified against the working `qwen3.8-27b-q4` rung too (zero
`load_tensors`/`model buffer`/`offloaded` rows in its buffer, despite the print site being
`LLAMA_LOG_INFO` in b11810 `src/llama-model.cpp:2016`). The §2/§11 expectation "the split arrives at
C04" is therefore void by method on this box; §13.3 carries the substitute fingerprints.

### 13.3 Buffer-class quantification (Vulkan_Host vs CPU_Mapped — AC1 fingerprint intent)

- Session C clean teardown printed the `~llama_context` accounting [SSE, 22:00:5xZ]:
  `Vulkan0 compute buffer size of 2070.8440 MiB` and `Vulkan_Host compute buffer size of 614.5625 MiB`
  — the whole observed **Vulkan_Host** residency is ≈ 0.6 GiB (under 1 GiB) vs the pre-fix class
  split recorded from upstream #30987 (§2: `Vulkan_Host model buffer 40681 MiB`) and §3's 55.8+4.75
  GiB pinned demand arithmetic — ~65× smaller than the crash-regime Vulkan_Host weight buffer.
- Experts placement under the new regime: the `-ot`-overridden 144 tensors (51.99 GiB, §5) bind to
  the file-backed **CPU_Mapped** buffer class (the mmap loader warning above names the combination;
  RESEARCH §4.3 maintainers' workaround) — reclaimable page cache, not GTT pins.
- Host-side corroboration (§13.5 table): MemAvailable never fell below 102.5 GiB with the 83.8 GiB
  model resident and active while the pod working set read 85.3–98.7 GiB — the >13 GiB delta of the
  working set beyond non-reclaimable demand is reclaimable file-backed pages; the pinned regime
  converted the same model into unreclaimable GTT/anonymous memory and died at the 62.54 GiB GTT
  budget (§3) before such RSS even completed.

### 13.4 Journal-clean proof — AC2

Window 2026-10-26T16:14:30Z → 22:26Z (config rollout; all four loads; ~45 min active serving
including 50k-token prefills; agent attempt; +10 min tail). Stream
`{cluster="gpu-ai", job="integrations/kubernetes/journal"}` [Loki — read path RECOVERED, C01's 502
no longer applies]:

| journal_clean_patterns (all four per procedure) | matches |
|---|---|
| `amdgpu_vm_validate` | 0 matches — clean |
| `BO_VA` | 0 matches — clean |
| `command submission` | 0 matches — clean |
| `ring .* timeout` | 0 matches — clean |

Sensitivity control: identical selector+filter returns matches in the 03:25–03:45Z crash window
(§1's 1772-line flood; e.g. `amdgpu 0000:c2:00.0: [drm] *ERROR* amdgpu_vm_validate() failed.`)
[Loki] — the zero rows above are discrimination, not missing data. Zero `*ERROR*` lines anywhere in
the post-landing window [Loki]. One non-contract WARN recorded verbatim: 17:12:51Z
`amdgpu 0000:c2:00.0: Fence fallback timer expired on ring comp_1.1.0` (level=warning) — matches
none of the four patterns, no reset/hang/device-lost line before or after it, serving unaffected
(loads B/C/D all passed health afterwards, 50k-token prefills completed). Node ai-gpu **Ready**
throughout [MCP]; pod **0 unexplained restarts** since rollout. Trio running-state: documented clean
reload cycles — matrix preload targets [home-3b-v3, qwen3-embedding-0.6b, qwen3.6-35b-a3b-q8,
qwen3.8-27b-q4/q6] at 16:16:21Z / 22:00:58Z / 22:21:04Z with health passes 22:01:07Z / 22:21:20Z;
solo-rung eviction of the trio during loads is the operator-accepted scheduled consequence
(DECISIONS 2026-10-26). Agent-side: one single load attempt, no retry loops; kernel `lockup_timeout`
(30000 ms, §4) and all `/sys/module` params left **untouched** — no host change in any branch.

### 13.5 Memory accounting at load-active peak — AC5 numbers

| moment (UTC) | state | MemAvailable GiB | pod working-set GiB |
|---|---|---|---|
| 03:35 (§1 era) | pinned attempt crashed, memory freed | 83.22 | n/a (old pod) |
| 14:08 (§7) | pre-fix comparison: 27b-q6 pinned + mmap PLE | 72.73 | — |
| 21:50 | flash-next-q3 resident, 50k-ctx churn | 106.12 | 97.76 |
| 21:55 | resident, active | 105.45 | 98.67 |
| 22:00 | resident, final requests | 102.99 | 89.00 |
| 22:00:50 | teardown | 102.56 | 85.34 |

`free -h` mirrors the [PROM] rows (C01 §7 precedent; MemTotal 125.08 GiB re-verified 22:1xZ).
Non-reclaimable demand under the new regime ≈ **19–22 GiB** (MemTotal − MemAvailable at peak: KV
≈3 GiB + Vulkan0 compute ≈2.1 GiB + runtime anon/misc); weights ≈80 GiB stay reclaimable page
cache. Headroom table, pre-fix vs post-fix: the pinned regime demanded 62–67 GiB of *GTT-pinned*
RAM against the 62.54 GiB budget (crash, §3); the mmap regime pins ≈0 GiB of weights, device/GTT
demand ≈10–13 GiB — **≈50 GiB GTT headroom** where pre-fix there was none.

q4 decision input (chunk task 7): q4 = 103.7 GiB weights, same regime → device/GTT demand
essentially unchanged (~10–13 GiB + ~1–2 GiB denser GPU-resident share; fits the 62.54 GiB budget
comfortably); host side = 103.7 GiB file-backed + ~20 GiB non-reclaimable ≈ 124 GiB vs MemTotal
125.08 — fits only SOLO with page-cache reclaim pressure at 262k-ctx churn (the family comment's
own "tight against ~125 GiB, SOLO only" reading). Verdict: technically testable next under the same
one-attempt protocol — **operator/coord decision, DECISIONS.md entry pending (coord-owned)**.

### 13.6 Serve smoke + long-prefill probe — AC1/AC3

- Serve smoke (sane completion) — on-record for this exact config through the operator's live
  clients: activity captures (agent-readable, `has_capture: true`) incl. id 168 fnq3
  `input 5019 / output 549, prompt 164.12 t/s, decode 10.89 t/s`, id 167 `input 50593 /
  output 726 @ 202.15/6.71 t/s` — coherent served answers, HTTP 200 [HTTP activity API].
  Agent-literal POSTs: environment-limited, recorded honestly — the sandbox egress proxy swallows
  POST bodies (499 at client timeouts; GETs unaffected), and the in-cluster UI channel got the
  queue/status stream only: request id 182 (the consented trigger) completed 22:20:46Z with the
  llama-swap loading-status narrative, **not** a model answer, because load D was evicted 0.6 s
  post-health before forwarding (§13.7 race) — capture `GET /api/captures/182` holds the full
  exchange [HTTP]. The AC1 "reached running" gate is met by four health-passed loads; the
  "sane completion" gate is met by the recorded captures above.
- Long-prefill probe (runtime ring-timeout class, procedure step `long-prefill-probe`): server-side
  records from the live buffer [SSE], all under the fixed regime:
  `prompt eval time = 102546.76 ms / 21723 tokens (211.84 tokens per second)` (concurrent slot),
  `prompt eval time = 250275.75 ms / 50593 tokens (202.15 tokens per second)` + `cache_tokens 49238`
  reuse, decodes 6.71–15.43 t/s, every slot `stop processing: ... truncated = 0`, clean teardown —
  prefills **far beyond the 8–16k requirement, clean**. No ring-timeout, no DeviceLost: the
  llama-side mitigations (`GGML_VK_MAX_NODES_PER_SUBMIT`, `-ub 512`) were therefore NOT applied
  (procedure rule: mitigate only if the class bites); kernel params untouched in every branch.
  The agent's own ~8k-token drill probe (31,167 chars, fired 22:24Z) was still FIFO-starved behind
  the operator's live 26-min 135,864-token request when cancelled client-side at 22:26Z to stop
  surprise loads during production use — recorded as environment limitation, not a model failure.

### 13.7 Gate 2 — MTP re-add (AC4): second gate passed on layout + render; cluster proof user-owned

- Gate conditions: C01 §5 hc-layout verdict **passed** (unsloth sidecar post-#28901; main GGUF
  carries `output_hc_norm.weight`) AND a passing, journal-clean no-MTP load (§13.2/§13.4) → gate 2
  open per DECISIONS two-gate path; operator GO covers "the next round of changes" (2026-10-26).
- Re-added: flash-next family `draft:` + `spec:` restored in `charts/llama-swap/values.yaml` — the
  exact removed lines from commit 947c3eec9 (`draft: unsloth/Qwen3.8-Flash-Next-GGUF:mtp-Qwen3.8-Flash-Next-Q8_0`,
  `spec: {type: draft-mtp, draft_n_max: 2}`) plus the orca-q6 rung-level `spec:` (TEST_SPEC §8.2:
  the orca first-cut removal included it). Orca keeps the documented probe-on-miss path: embedded
  MTP first (qwen38-orca publisher convention), else the standalone sidecar
  `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF:MTP-draft.gguf` — NOTE the UPPERCASE `MTP-` file
  name, the llama.cpp `mtp-` sidecar match is case-sensitive (TEST_SPEC §7(F)).
- Validation: helm lint/template re-executed; full chart suite re-run — the first-cut absence
  contracts flip red **by design** (5× `test_c03_ac1_first_cut_has_no_mtp_draft_or_spec` +
  1× `test_c04_1_flashnext_mtp_draft_wired` hardcode the pre-gate-2 state and do not model the
  re-add; routed to the test session as validation_at_fault via RESULT — tests untouched by dev).
- The second consented load of the MTP-enabled rung executes only after the operator lands the
  branch to main (ArgoCD pulls main; PR is user-owned — agents never push/merge): same
  journal-watch, fingerprint and one-attempt discipline; trio eviction accepted. Final serving
  regime at record time: **`--load-mode mmap` on, `--fit off` on, MTP re-added on the branch /
  off on the cluster until landing** — all §13.2/§13.6 timings are the no-MTP regime.
- Scheduling follow-ups (not kernel/journal issues; no config change made outside the consented
  scope): (1) load D was evicted 0.6 s after health by a same-second trio-preload matrix event —
  a llama-swap v265 solo-vs-preload race worth an operator look; (2) queued solo requests starve
  behind long in-flight main-set streams (~10 min observed); (3) agent POSTs through the sandbox
  egress proxy do not reach workloads (bodies swallowed) — use the UI same-origin channel or an
  operator-side curl for future smoke needs.

### 13.8 C04 provenance appendix

Readonly MCP: `readonly-ai-gpu-kubernetes` (pods/pods_get/pods_top, nodes via resources_list,
ConfigMap, argoproj Applications), `readonly-global-grafana` (Loki label/stats/LogQL incl. the
crash-window sensitivity control + Prometheus instants; datasources `prometheus`/`P8E80F9AEF21F6940`).
HTTP: `llama.gpu-ai.spencerslab.com` (+ public alias) — /health, /running, /api/hardware, /logs,
/api/metrics/activity, /api/captures/182, POST /v1/chat/completions (trigger + probes), and the
same-origin UI fetch channel (playwright MCP) for `/logs/stream/qwen3.8-flash-next-q3` replays
(37,190 B, 4 sessions) + the served-request record. GitHub API: b11810 `src/llama-model.cpp` print
site + llama-swap `internal/server/{server,log}.go`, `internal/logmon/group.go` (log-routing
forensics). Repo-side: helm v3.16.4 re-provisioned to /tmp/opencode/bin (sha256 fc3073279…,
FRICTION item), chart suite before/after edits. No admin MCP, no kubectl apply, no version/image-tag
bump, no test edit, no kernel/host mutation, no user-run host command was needed for this chunk.
