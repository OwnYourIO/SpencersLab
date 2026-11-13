# RESEARCH.md — cf-143 feat-radiance-replaces-strata (AD-143, Pre Research round)

Deep-research verdict on the card's deployment guide, the three-way "radiance"
identity collision, and the 8-sessions/KV-to-RAM question. Every claim below
carries a source actually read this round (accessed 2026-11-11 unless noted);
[S#] keys point to the Sources list. Per-RQ verdicts use
VERIFIED / CORRECTED / UNVERIFIABLE + confidence (H/M/L).

## TLDR (for the plan question round)

1. **Identity is resolved, and the card's target is real**: `StillDeadcode/radiance`
   is a standalone C++/HIP inference engine (not a llama.cpp fork, not vLLM),
   successor to `StillDeadcode/vllm-radiance`; `magiccodingman/vllm-radiance`
   (charts/vllm today) is a community continuation of that old vLLM fork — a
   different artifact; `Niko1221/Strata` is an unrelated engine. The binary that
   speaks OpenAI HTTP for llama-swap is `radiance` (`/opt/radiance/bin/radiance`,
   image entrypoint, **no `serve` verb**). Tag `1.17.0` exists on Docker Hub and
   its **amd64 image manifest digest is exactly the guide's `sha256:6fb0e99b…`**
   (the tag's index digest is `sha256:c2acbaa3…` — pin shape matters).
2. **Priority/preemption: the card's fear is inverted.** Radiance implements
   vLLM's exact scheduling model — *priority queue + preemption by recompute* —
   with a request `priority` field where **higher wins (default 0)**. The lab's
   current polarity table (urgent=1, low=9, vLLM-style lower-wins) would run
   BACKWARDS on radiance. That is a real wiring bug to avoid, not a missing
   feature. Preemption is automatic under KV pressure; `--preempt-wait-ms`
   (5000) escalates to evicting lowest-priority running requests.
3. **"KV offloaded to system RAM" exists as two named mechanisms** — `--kv-resident`
   (streams Flash-Next's sparse QSA KV group from pinned host RAM, ring on card;
   supported for exactly `qwen4exp_fp8` + `glm5next`) and `--prefix-cache-mib`
   (finished conversations demote to a host tier and restore instead of
   re-prefilling). But on THIS box the 8×long-context wall is not RAM — it is
   **VRAM pool + the x4 link**. Measured community data on Gen4 x4: TP1
   Flash-Next prefill collapses to **~454 tok/s at 55k** (vs 2,640 on x16);
   the 27B is nearly link-immune (−5% pp on x4, weights fully VRAM-resident).
   8 sessions on one R9700 is a q27-shaped problem (solved, with receipts) and
   an fn-tp1-shaped compromise (works, minutes-class TTFT on long prompts).
4. **Structural answer (RQ5): peer Deployment is the right first shape** —
   radiance as a llama-swap *child* demonstrably works (llama-swap#1255 user
   runs exactly that with the repo's own `ulimit -n` wrapper idiom), but as a
   child every model swap pays the 66 GiB reload and the io_uring/pin budget
   gets inherited from the llama-swap pod (root UID, 8 MiB memlock). llmkube's
   merged production manifest proves a clean non-privileged peer pod:
   `/health` probes (auth-exempt), `--api-key-env`, dedicated UID, no memlock
   drop-in. One model per pod, radiance never "swaps" — like vllm today, not
   like strata.
5. **The guide's headline numbers are mostly real but mis-attributed or stale**:
   `--expert-vs-cache-ratio` is **not a v1.17.0 flag** (engine derives the
   split); the "fn-tp1 32K/4seq/38600" recipe is the *swift1.5 HF card*, while
   v1.17.0's shipped `flashnext-tp1.yaml` serves **200K × 4 seq with a 43000
   pool and 4096-token chunks**; the 116.0/93.5 tok/s and the 15.7 GiB/60 KB-per-token
   TP2 pool are **Thomas Wilde's Z490 measurements**, not the creator's card;
   and Wilde's Nov-11 post documents a **pinned-demotion OOM-kill trap** that
   directly threatens the lab's 125 GiB box.

## Sources

| # | URL | What it is | Accessed |
|---|---|---|---|
| S1 | codeberg.org/StillDeadcode/radiance (repo page + README @ tag v1.17.0) | engine README: API surfaces, model table, pack sizes, ReBAR, pin cap, per-model flags | 2026-11-11 |
| S2 | codeberg.org/api/v1/repos/StillDeadcode/radiance/raw/docs/GUIDE.md?ref=v1.17.0 | user guide @ 1.17.0 (295 KB): §4.3 memory/tiers, §4.4 long ctx, §4.4.1 KV streaming, §4.5 prefill, §4.6 speculation, §4.7 TP/P2P, §4.8 host tier, §4.11 every flag, §5.1 endpoints, §5.7/5.8 fields, §6.3 metrics, §6.6 security, §7.1 startup report, §8 env | 2026-11-11 |
| S3 | same base, docs/TOOLS.md, docs/DOCKER.md, docs/TP3.md, docs/PREPARING_YOUR_RIG.md, STRIX_HALOD_RADIANCE.md, spec.md, deploy/compose/* (flashnext.yaml, flashnext-tp1.yaml, qwen3.8-27b-mxfp4.yaml, common.yaml, .env.example) | tools/flags, image layout + compose posture, TP3 notes, host prep, libhalo log, design spec (§7 scheduling), the shipped recipes | 2026-11-11 |
| S4 | hub.docker.com/v2/repositories/stilldeadcode/radiance/tags/?page_size=100 | 39 tags; 1.17.0 pushed 2026-11-04T18:16Z, amd64 image digest sha256:6fb0e99b…, index digest sha256:c2acbaa3…; 1.16.0 sha256:b1017ce0…; first push 1.0.0 2026-10-04 | 2026-11-11 |
| S5 | huggingface.co API + raw READMEs: StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe, swift1.5-qwen3.8-next-flash-fp8-iq4r-moe, qwen3.8-27b-mxfp4 | pack existence (gated: False), exact byte sizes + lfs sha256, TP1/TP2 recipes, protected-expert counts, DFlash2, MTP 62–88%, TP2 ~15 ms step, KL tables | 2026-11-11 |
| S6 | stilldeadco.de + radiance.stilldeadco.de/changelog | "Latest release v1.17.0"; release cadence (1.15.0 30 Oct, 1.15.1 31 Oct, 1.16.0 2 Nov, 1.17.0 4 Nov); 1.17.0 contents (IQR-V4, --gpu-memory-mib, disk=DIR) | 2026-11-11 |
| S7 | forum.level1techs.com/t/257789.json (thread OP + page 5 via search) | "Ultimate 2x R9700 guide" (v1.2.3 era): lineage paragraph (vllm-radiance→radiance), 423 MB image, docker run posture (memlock -1, shm 32g, seccomp unconfined), "first load … ~66 GiB … about 4 minutes", speed tables; page-5 jackal830 x4-ladder measurements | 2026-11-11 |
| S8 | thomaswildetech.com/blog/2026-11-08/what-a-gen4-board-costs-… | Gen4 ladder: fn TP2 15.7 GiB pool ~60 KB/token, 8-lane 64k 252 agg → 278 with spec off, q27 TP1 116.0/93.5, "262k boots, KV refuses past 12.46 GiB", host-RAM table, DFlash2-in-pack | 2026-11-11 |
| S9 | thomaswildetech.com/blog/2026-11-11/p2p-forced-tested-closed-… | forced P2P on Rocket Lake → completion timeouts ("closed with evidence"); zram/`systemd.zram=0`; **prefix-cache demotion burst OOM**; kernel 7.3.3 `mem_info_vram_vis_total` regression; AMD-RC P2P kernel whitelist note | 2026-11-11 |
| S10 | github.com/mostlygeek/llama-swap/issues/1255 | radiance 1.10 as llama-swap child; spawner forces child soft nofile=1024; EMFILE failure ("io_uring refused", "KV pool … card would not back it"); fix = `ulimit -n 524288; exec radiance`; probe table 1024/524288 | 2026-11-11 |
| S11 | api.github.com PRs dsluo/homelab #2032/#2070/#2127/#2184 + raw llmkube `qwen3-8-flash-next.yaml` (main) | production k8s (Talos, 2×R9700, 62 GiB): pod pinned `1.17.0@sha256:6fb0e99b…`, /health probes 180×10s, io_uring memlock-per-UID, seccomp localhost profile with io_uring, TP2 262144 recipe, req 40Gi/lim 48Gi, ngram disk, vision+embedding RAM; renovate tag PRs (two repos) | 2026-11-11 |
| S12 | api.github.com audiagentic/bigcherry PR #512 | 8-session fill test; host KV tier funded from shrunk pool; "moving the n-gram table to disk costs about 10%"; 24 GiB tier refused by engine's own memory check | 2026-11-11 |
| S13 | api.github.com repos/ROCm/k8s-device-plugin (plugin.go, naming.go, alloc.go @ v1.31.0.9, releases, helm index) + rocm.github.io/k8s-device-plugin/index.yaml | Allocate() = /dev/kfd + cardN/renderDN, no env visibility, no occupancy persistence across restart; nodeId-ascending candidate pick; PR #246 `product` naming merged 2026-10-19 (first in v1.31.0.12); chart 0.22.0 appVersion 1.31.0.9 | 2026-11-11 |
| S14 | readonly-ai-gpu-kubernetes live reads (node ai-gpu, plugin pod spec+logs, pods stats) | capacity=allocatable amd.com/gpu:2; kernel 7.3.0-1-default k3s v1.36.5 containerd 2.3.4-k3s1.36; plugin parses kfd topology nodes, Devices map c4:00.0 (card1/renderD128/nodeId0) + c5:00.0; plugin 19 restarts (last 2026-11-10 14:31Z); strata pod RSS 73.9 GiB / workingSet 109.05 GiB of the 125.08 GiB node (110Gi container limit) | 2026-11-11 |
| S15 | repo files: containers/vllm-radiance-mxfp4/Dockerfile + README; charts/vllm/values.yaml:49-55,430-442; EXPLORE.md | magiccodingman lineage ("tracks and credits Deadcode's vllm-radiance + libr4d"); plugin-allocated-8060S crash 2026-11-07; host enumeration 0=R9700; node /dev/kfd group 486 mode 660; setuid caps law | 2026-11-11 |
| S16 | github.com/ROCm/TheRock/issues/9259 (search snippet) + reddit/LocalLLaMA + llama-perf/raytone-lab/llamaperf aggregators | radiance:latest was 1.16.0 rev 769b4c64 (gfx1201/gfx11-generic/gfx1151, ROCm 10.1 bundled, no host ROCm); Strata-vs-Radiance field reports; vllm-sly-radiance third fork existence | 2026-11-11 |
| S17 | devicehunt.com + strixhalo.wiki/Guides/VM_iGPU_Passthrough + technicalife.net | 8060S = PCI 1002:1586 (audio 1002:1640); vfio-pci bind ids=1002:1586,1002:1640 removes it from host amdgpu | 2026-11-11 |
| S18 | k3s-io/k3s k3s.service (main + v1.36.4+k3s1) | unit sets LimitNOFILE=1048576; no LimitMEMLOCK (systemd default 8 MiB inherited); drop-in path /etc/systemd/system/k3s.service.d/ | 2026-11-11 |
| S19 | forum.level1techs.com Franken Strix Halo thread (search-cited) + daimonionnn/multi-gpu-llm-toolkit oculink-amd-dgpu.md | PEX88xxx = Gen4 switches (89xxx Gen5); R9700↔R9700 through external switch ~13.4 GB/s symmetric (switch-fabric bound); Strix-Halo OCuLink boards ~120 W AMD-dGPU cap norm; EVO-X3 OCuLink Gen4 x4; RCCL no gfx1151 kernels | 2026-11-11 |
| S20 | api.github.com Niko1221/Strata PR #3636 + repo meta | Strata = "Qwen3.8-Flash-Next on any consumer hardware: one-click install…" (Niko1221); #3636 = same-hardware benchmark: 124 GB Strix + R9700 OCuLink Gen4 x4, R9700-alone-with-arena-in-RAM beats the split (64k prompt 1,627→2,530 tok/s; 4 concurrent 136-140 tok/s sum; dGPU-first enumeration) | 2026-11-11 |

## RQ0 — IDENTITY (blocking) — RESOLVED

**(a) `stilldeadcode/radiance` (Codeberg, Docker Hub, v1.17.0):** its own
engine, not a fork. "An inference server for AMD GPUs, in C++ and HIP: language
models, and image, video, speech and music generation. Its HTTP API speaks
OpenAI's chat, completions, Responses, images, audio and video APIs,
Anthropic's Messages API and llama-server's native one" [S1]. Apache-2.0
(Deadcode et al.), 38 git tags / 930 commits; modular core + `.so` plugins for
architectures, kernels, quantisers (libr4d gfx1200/1201, libr3d gfx11xx,
libhalo gfx1151, libavx host) [S1][S3 DOCKER.md]. It is **not a llama.cpp fork**
— llama.cpp lineage is "the tech stack" idea (C++/HIP + vLLM's
concurrency/batching/paged-attention concepts per the author in [S7]) — though
some llama.cpp parts are vendored in `vendor/` [S2 §1.1]. Lineage:
vllm-radiance (a patched vLLM with libr4d kernels) → "The author then ditched
vLLM entirely and rewrote everything from scratch as Radiance" [S7]; the old
vLLM fork remains archived as `StillDeadcode/vllm-radiance` (Docker Hub image
exists: gfx1201-only vLLM 0.27.1 + libr4d, "TP=2 is the only configuration
tested" per its hub page, [S16]).

**(b) `magiccodingman/vllm-radiance` / `ghcr.io/ownyourio/vllm-radiance-mxfp4`
(charts/vllm today):** a *continuation of the old vLLM fork*, not the engine.
Repo's own ledger: "This line **continues** the stilldeadcode vLLM/R9700 story:
magiccodingman tracks and credits Deadcode's vllm-radiance + libr4d work and
additionally ports the native Quark MXFP4/W4A8 work" [S15]. Its entrypoint is
`/opt/radiance_entrypoint.sh` exec'ing `vllm serve` [EXPLORE §2] — so the
`RADIANCE_*` env vars in charts/vllm belong to **that fork**, a third API
surface. No relation to the new engine's flags.

**(c) `Niko1221/Strata`:** unrelated engine (different author/repo): "Qwen3.8-Flash-Next
on any consumer hardware: one-click install for Windows / Linux. Strata
inference" [S20]. The EXPLORE same-author hypothesis is **refuted** — nothing
links Strata to StillDeadcode. Strata and Radiance appear side-by-side as
distinct engines in field reports [S16][S8][S20]. Radiance is a *replacement
competitor*, not a rebrand.

**Binary + `radiance serve`:** the OpenAI-compatible HTTP server is `radiance`
itself (image entrypoint; `/opt/radiance/bin/radiance` [S3 DOCKER.md, S11]).
**There is no `serve` subcommand** — invocation is
`radiance --model <file.rad|checkpoint-dir|hf/repo-id> --port N <flags>` [S1][S2
§4.1]; `radiance serve` would be an invalid argv (the `serve` verb belongs to
*Strata* — repo strata cmd: `strata serve --profile …` — and to *vLLM*, which is
why the card guide mis-spoke). VERIFIED, high confidence.

**Artifact pin verification:** Docker Hub `stilldeadcode/radiance`:
count=39 tags, first push 2026-10-04 (1.0.0), newest numeric tag **1.17.0
pushed 2026-11-04T18:16:10Z** [S4] — matches the guide ("Latest release" per
stilldeadco.de [S6]). `:latest` currently re-points at the same 1.17.0 index.
Digest nuance (drift-risk for the plan): the **tag's manifest-index digest is
`sha256:6fb0e99b…`'s wrapper `sha256:c2acbaa373c89272ec47a22befa1cf04d2ddf1de51c2baf534f5273e517f7100`**,
while `sha256:6fb0e99bfb862e17cc15cb7b2f116c7dbdc831df59f82456a0691122e6cf5330`
is the **amd64 image manifest** digest [S4]. llmkube pins exactly
`1.17.0@sha256:6fb0e99b…` (valid amd64 manifest pin) [S11]. Both spellings are
reproducible; the repo must record *which* it uses (repo precedent is tag +
digest-in-comment, [S15]/EXPLORE §6). 1.16.0 = `sha256:b1017ce0…` ✓ (single-arch
config digest, matches guide). No 1.18.x exists as of 2026-11-11 [S4].
Release cadence: 38 tags in ~5.4 weeks (Oct 4 → Nov 4) = **1–2 releases/week,
faster than the guide's "weekly" estimate** [S4][S6]; the guide's "main moved
past 1.17.0" is exact: `scheduler: --prefill-interleave defaults to auto:1`
committed 2026-11-05, post-v1.17.0 [S1 activity].

**Model packs — all exist, ungated** (`gated: False` in HF API [S5]):

| pack | bytes (exact) | = | guide claim | lfs sha256 (current) |
|---|---|---|---|---|
| qwen3.8-next-flash-fp8-iq4r-moe.rad | 121,969,901,568 | 113.60 GiB | 113.6 GiB ✓ | 0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20 |
| swift1.5-qwen3.8-next-flash-fp8-iq4r-moe.rad | 122,013,646,848 | 113.64 GiB | guide said 113.5 (≈✓, 0.14% off) | a29c0d8a580a041a8620d318b1778b40bd2733b43271ce293aa4632b3ae8cf87 |
| qwen3.8-27b-mxfp4.rad | 19,377,119,232 | 18.05 GiB ✓ | 18.05 GiB | a4908940c568f5f9dd24e88f46aefe9ac2ae07dfec023a2eaa1d14dcaa3df4f8 |

Pack facts verified from the HF cards: fn pack = 4-bit codebook (w4nl64,
FWHT-128) GPTQ+3×CD experts with **ten** bf16-protected experts, int8 (W8A8)
trunk, MTP depth 3, vision tower, **262,144 trained / served at 200K**, KL
0.0789 mean / 92.85% top-1 [S5] (guide's "113.6 GiB … ten bf16-carrying
experts … 262,144/200K … MTP depth 3 … vision tower" all VERIFIED). The
n-gram/PLE table = **47.68 GiB** [S2 §4.3 "47.7 GiB"; S7 "47.68 GiB",
"51B-parameter n-gram/PLE table"]. q27 pack = AMD Quark AWQ-MXFP4 trunk **with
z-lab DFlash2 drafter merged** + vision tower, "262,144 trained; 200K tested",
needs radiance ≥1.2.3 [S5]. Swift1.5 twin: same recipe calibrated on ukisai's
finetune, **sixteen** protected experts, carries the published TP1 recipe
(guide ✓) — note Swift Open License adds a commercial-use clause irrelevant to
the homelab but worth a DECISIONS line.

## RQ1 — CAPACITY / KV-OFFLOAD (the owner's named bad assumption)

**Tiering model (VERIFIED from source @ v1.17.0 [S2 §4.3, §4.4.1, §4.8, §4.11]):**

- The card is split into resident weights + a paged KV pool; **no flag sets the
  split** — it is derived (`--gpu-headroom-mib` / `--gpu-memory-mib` claim the
  card, startup receipt prints every term). The guide's
  `--expert-vs-cache-ratio 0.82` **does not exist in v1.17.0** — grep of the
  whole flag table finds nothing; it appears only in the **stale HF model card**
  (card last modified 2026-10-03 [S5], before the split became derived).
  CORRECTED. (Concept §2.5: "Every pool is budgeted explicitly … a split the
  engine re-optimised on its own would make benchmarks irreproducible" — but
  budgeted from the printed card/claims, not a ratio knob.)
- `--host-pool-mib N` = **pinned host tier for weights (experts)**, *pinned per
  card* ("so the four-rank row pins 4 × 12 GiB = 48 GiB … that nothing else can
  use and the kernel cannot swap out" [S1]). With `--placement expert_tiered`
  (or auto) + a VMM-capable kernel, the KV cache is a **lending cache**: experts
  keep on-card what the pinned pool can't hold; the cache lends every
  non-live block back to the expert slab. The pool is bigger → fewer resident
  experts → *more* KV room ("a larger --host-pool-mib takes experts off the
  card and gives the cache more").
- Pinned-memory accounting: "The amdgpu driver caps what all processes together
  pin at the machine's RAM less 1/64 and 1.5 GiB; the pool is locked user
  memory, which ttm.pages_limit does not count" — the guide's cap formula is
  VERIFIED *verbatim from the README* [S1]. On the lab's ~124 GiB box: cap ≈
  124 − 1.94 − 1.5 ≈ **120.6 GiB** (guide's number ✓ arithmetic).
- The "refuses unless 4 GiB free under limit" claim: the mechanism is
  `--host-headroom-mib` (default 4096): the embedding/ngram/tower RAM
  placements are refused when "the table cannot be held … under every memory
  cgroup the process sits in" [S2 §4.3]. Independently confirmed by llmkube
  #2070: "Radiance refuses to start unless 4 GiB stays free under the limit
  after its startup reservations; by the source" and #2127 "at 44Gi Radiance
  warned cgroup-limit" [S11]. VERIFIED (note: a snapshot-store floor can take
  back part of the reserve, down to 1 GiB — [S2 §4.8]).
- `--ngram-placement auto|vram|ram|disk[=DIR]` [S2 §4.3]: disk = streamed from
  the .rad via a host io_uring row cache (~85 MiB, O_DIRECT, ~half first-seen
  rows); ram = a pinned copy read by the card over the link (+12–40 s startup),
  refused if the table's size isn't free after pools+tier+slots+headroom under
  the cgroup. `ram=DIR` (tmpfs file) shares one table between two engines on
  different cards — with the driver counting the shared page **once per
  pinning process** (needs `amdgpu.no_system_mem_limit=1` for two engines, or
  the second pin is refused).
- `--weights-disk-tier` = experts that fit neither VRAM nor pool stream from
  the container via 4×32 MiB pinned windows; "meant for running a checkpoint
  as shipped, to calibrate or compare" — a bring-up/reference tier, not the
  production leg [S2 §4.3].

**"KV cache offloaded to system RAM" — what it concretely is for radiance:**
the KV cache's *live* half stays VRAM-paged (elastic, lends to experts); RAM
gets the KV through two mechanisms, both explicitly documented:

1. **`--prefix-cache-mib N` — host tier for finished conversations** [S2 §4.8]:
   when a request completes, its KV blocks are *copied* to host memory (keeping
   the VRAM copy until it's needed for something else — the expert-loan or a
   new admission); a returning conversation restores from the host tier
   ("Restoring a 200K-token turn costs a copy over PCIe; recomputing it costs
   minutes"). Hybrid state: linear-state snapshots always live in host pinned
   memory (`--checkpoint-slots`, ~113.5 MiB/slot on Flash-Next, 80 slots ≈
   8.87 GiB at 8 seqs, auto-capped at 1/8 host RAM) [S2 §4.8]. **This is the
   lab's "8 sessions" lever**: sessions that are idle sit in RAM; VRAM only
   pays for the ones decoding *now*.
2. **`--kv-resident N` — KV streaming for contexts the card can't hold**
   [S2 §4.4.1, docs/KV-STREAMING.md]: the **sparse attention group's entire KV**
   (QSA — supported exactly on `qwen4exp_fp8` = Flash-Next, and `glm5next`)
   lives in pinned host RAM with only a 32,768-token ring per group on the
   card. Measured: decode unchanged (±0.3%), prefill 1–2% *faster*, perplexity
   +0.5%; two 262k conversations on 2×16 GB cards went from 3.84→0.74 GiB
   VRAM/card + 3.22 GiB host/card. **Mutually exclusive with the prefix-cache
   host tier** (tier is off while a group streams; prefix hits still work from
   VRAM only) and **host copy reserved max-num-seqs × max-model-len however
   short the requests** — and at `--tp 1` "the host copy for 2 × 262k (6.00
   GiB) does not fit beside the weights, and the start is refused" on the
   reference rig [S2 §4.4.1]. So: radiance HAS a KV host tier (unlike the guide
   framing "KV stays VRAM"), but with two shapes that can't both be on.

**Per-token cost — a real contradiction the plan must resolve on-target:**
[S2 §4.3] worked example: Flash-Next paged groups `kv_attn` 26.00 KiB +
`kv_qsa_bkey` 3.25 KiB **per 4-token block** → "a token costs 7.32 KiB and a
200K-token sequence 1.43 GiB"; prefix-cached sessions occupy ≈1.8× context in
pool tokens. But field pools: 4×R9700 TP4 = "11.6 GiB per card … 1.6M tokens,
or 8 full 200K sessions" [S16 reddit] → ~30 KiB/token per card; Wilde's TP2 =
"~15.7 GiB total, ~60 KB per token, one 262k whale or ~4 simultaneous 64k"
[S8]. 7.32 / 30 / 60 KiB-per-token — the doc example counts only the two named
paged groups (delta-net state 54 MiB/sequence×2-copies and block tables are
separate [S2 §4.4]); the field numbers include everything the receipt charges
in that build. **Verdict: don't plan off any per-token figure; the startup
receipt prints "kv: the pool backs N% of the worst case … M full-length
sessions" — measure it (S2 §4.3 literally instructs this).** Guide's "TP2 KV
~15.7 GiB pool at ~60 KB/token → one 262k whale or ~4×64k (270K tokens)" =
VERIFIED as Wilde's measurement [S8], flagged as Gen4-Z490-build-specific
(engine version/link/RAM differ from the lab).

**Guide's fn-tp1 row vs lab reality — CORRECTED recipe (v1.17.0 shipped):**
the guide's "32K ctx, 4 seqs, 49 GiB pinned, 60Gi limit" is a mash-up. Actual
published recipes [S3 compose, S5 card]:

| source | recipe |
|---|---|
| v1.17.0 `flashnext-tp1.yaml` | `--tp 1 --max-model-len 200000 --max-num-seqs 4 --placement expert_tiered --host-pool-mib 43000 --gpu-headroom-mib 96 --kv-cache-dtype fp8 --prefix-cache-mib 4096 --num-speculative-tokens 3 --max-num-batched-tokens 4096 --checkpoint-interval 4096` (+ `--api-key-env`, `--host ::`); header: pins ~49 GiB total, "at 4 sequences the cache holds 301K tokens, one and a half 200K-token sessions"; n-gram on disk; 26K-prompt prefill **2545 vs 1413 tok/s** at 4096- vs 2048-chunks |
| swift1.5 HF card TP1 (the guide's row) | `--tp 1 --max-model-len 32768 --max-num-seqs 4 --placement expert_tiered --weights-disk-tier --ngram-placement disk --host-pool-mib 38600 --num-speculative-tokens 3 --max-num-batched-tokens 2048`, "about 40 GB free host RAM", smoke-verified incl. **62–88% MTP drafts accepted** and 4 concurrent |
| fn HF card TP2 | `--tp 2 --tp-wire wht6 --max-num-seqs 8 --max-model-len 200000 --placement expert_tiered --host-pool-mib 12288 --gpu-headroom-mib 96 --kv-cache-dtype fp8 --num-speculative-tokens 3 --max-num-batched-tokens 2048 (+ stale --expert-vs-cache-ratio)`; measured ~15 ms step @ 2.4 accepted ≈ **160 tok/s 1-stream, ~6,400 tok/s prefill @26K** on 2×R9700 (creator rig, Gen5 x8/x8 P2P) |

Prefill arithmetic on the lab's OCuLink **Gen4 x4**: [S7 page5, jackal830,
Radiance 1.8.1] measured it on hardware with the same link class: card↔host
7.0–7.2 GB/s; Flash-Next TP1 **55k prompt: 2,640 tok/s on x16 → 454 tok/s on
x4**; "/stats showed ~15 MB per token read across the link; 15 MB ÷ 7 GB/s
predicts the 455 measured"; TP2 (x16+x4) hid most of it (~2,450 tok/s, stager
2.45 MB/token/card ≈ 85% of the x4 link); "a model that fits in VRAM barely
cares — 27B MXFP4 on x4 is ~5% slower than x16". So the guide's "few hundred
tok/s at batched 2048" is **VERIFIED-as-estimate and now measured**: the lab
can expect ≈450–600 tok/s TP1-fn prefill at long depth (chunk 4096 ≈ 2× better,
[S3 compose]), while q27 on the same link is ~unaffected. Strata today on
identical hardware (same link, same box class, #3636): 64k prompt 2,530 tok/s
with the arena in RAM [S20] — the plan must decide if the quality leg's
minutes-class TTFT on TP1 is acceptable, since radiance has **no APU-lane
split mode** (libhalo serves on the 8060S as the only device; mixed
gfx1151+gfx1201 tensor ranks are not documented [S1][S2 §4.7]; the iGPU is not
radiance's second lane the way Strata's split or xct's `strixpro` use it
[S16 vuln.dev]).

**8 sessions × lab context budget — the derived envelope (mechanism-confirmed,
arithmetic flagged):** see "Serving envelope" below. Verdict on the owner's
hypothesis ("KV-to-RAM makes TP1 fn at ≥64K × 8 work"): **PARTIALLY CONFIRMED
with a caveat** — RAM offload mechanisms exist and bigcherry #512 *demonstrates
8 sessions* (1M-token fill on their 4-GPU rig: 2,945 tok/s cold after moving
pool 22 GiB→9 GiB + funding a 12 GiB host KV tier; 6-stream slowest-first-token
3.6→2.2 s) [S12]; on a single 32 GiB card the binding limits are (a) the VRAM
pool: 8×200K live sessions want ~2.9M pool tokens × the receipt rate — v1.17.0's
TP1 recipe backs 301K tokens at 4 seqs [S3], so 8 long live sessions need
`--kv-resident` (RAM mirror ≈ 12 KiB/token → 8×200K ≈ **~19 GiB pinned** host
copy) at which point the prefix-cache tier is force-off; or (b) accept
"few live + host-tier for idle" with `--prefix-cache-mib` (tier bytes per
session = attention blocks only: at the 7.32 KiB/token doc rate 8×64K ≈ 3.7
GiB — fits a 8 GiB tier like llmkube's; at Wilde's 60 KB/token it doesn't —
measure). Either way **the link, not RAM, sets TTFT on fn-tp1** (454 tok/s at
55k measured). fn-tp1-ram (ngram in RAM, ~95–100 GiB pinned, guide's "only if
radiance is the sole large tenant"): arithmetic on 124 GiB works (42.0 pool +
47.7 table + snapshots 8.9 + embed ~1 + tier/arena + headroom ≈ 105–110 <
120.6) **but** Wilde's Nov-11 post proves the **demotion-burst OOM trap**: when
experts reclaim VRAM, idle sessions demote *pinned* in one burst (9.4 GiB in
2 s observed), invisible to reclaim — on a 124 GiB box sharing nothing else
it's survivable only with ≥15 GiB genuinely free; bigcherry's "24 GiB tier is
refused by the engine's own memory check" is the same physics [S9][S12].
Speed delta ngram ram-vs-disk: **~10%** VERIFIED (bigcherry #512: "moving the
n-gram table to disk costs about 10%"; L1T page 5 voices say ~3% and "almost no
difference at c=4" [S12][S7] — treat as 3–10%, workload-dependent; the guide's
"~10% per bigcherry PR#512" is correctly attributed).

## RQ2 — PRIORITY & PREEMPTION — RESOLVED, CARD'S SUSPICION INVERTED

Radiance **supports both**, and the scheduling model is explicitly vLLM's:
- spec.md §7.1: "The scheduling model follows vLLM's. Continuous batching,
  chunked prefill, **priority queue, preemption by recompute**" [S3 spec].
- scheduler.h: running/waiting lists "kept sorted by (**priority desc**,
  arrival asc); the preemption victim is the back; admission takes the
  front"; a preempted request keeps its arrival stamp (re-enters ahead of
  later arrivals) [S3 scheduler.h].
- Request field `priority` accepted on the API (§5.7 *implemented* table, not
  the unimplemented list), default `0` (`oai.h: int priority = 0`) [S2, S3].
- Flag `--preempt-wait-ms` (default 5000): "how long a preempted prefill may
  wait … before reclaiming cache blocks and **preempting lowest-priority
  running requests** until one overdue request can prefill" [S2 §4.11].
- Metrics: `vllm:num_requests_running/waiting`, `num_preemptions_total`,
  `gpu_cache_usage_perc` — a **vLLM-compat family** so existing dashboards
  work — plus `radiance:num_requests_preempted`, `preempt_forced_total` [S2
  §6.3]. Dashboard/`/stats` show fill; "a full pool causes preemption" (§6.1).

**Polarity landmine (CORRECTED, this is the load-bearing finding):** in
radiance, *higher* `priority` schedules first. The lab's current four-class
degradation is vLLM-polarity: catalog rows urgent=`body.priority: 1` /
default 5 / low 9, and `peers.vllm.filters.setParams."priority?" = 5`
(set-if-undefined floor) [EXPLORE §1a, §2]. Ported unchanged to radiance,
**urgent (1) becomes near-idle and low (9) becomes the preemption-proof top
lane** — and a radiance `priority: 0` default sits below the 5-floor. The card's
"handle that gracefully" is answered concretely: (1) flip the numbers when
targeting radiance (e.g. urgent=9, default=5, low=1 — or map in the peer
filters), (2) keep `setParams "priority?"` only if the value matches radiance
polarity, (3) the engine's own queueing already degrades gracefully:
`--max-queued-requests` (default 8×max-num-seqs) answers 429+`Retry-After`
rather than stalling, and `timeouts.responseHeader: 1800` (both lab peers)
survives long waits; matrix `evict_costs` stays the llama-swap-side preemption
lever but radiance-as-peer sits outside any matrix (no eviction semantics
between peers and children — EXPLORE §1a "peer models stay OUT of the outer
matrix"). If the plan wants llama-swap-side priority it has one knob only:
the body field, which radiance *honors*. No client-side queueing needed.
(Confidence H on existence/semantics/polarity — direct source; M on whether
priority also orders preemption *within* hybrid-group edge cases — not read.)

## RQ3 — POD SHAPE vs REPO REALITY (live cluster 2026-11-11)

- **Device plugin**: external helm chart `amd-gpu` **0.22.0** (verified present
  in the rocm.github.io index; appVersion **1.31.0.9**) [S13]; live DaemonSet
  `amd-gpu-device-plugin-daemonset-knf6w`, image `docker.io/rocm/k8s-device-plugin:1.31.0.9`,
  hostPath `/sys` + `/var/lib/kubelet/device-plugins`, system-node-critical,
  33d old, **19 restarts (last 2026-11-10T14:31Z)** [S14]. Logs show
  enumeration via `/sys/class/kfd/kfd/topology/nodes/*` and a two-device map —
  PCI `0000:c4:00.0` (card1/renderD128/nodeId 0) and `0000:c5:00.0` [S14]:
  **the plugin counts the 8060S and the R9700; node reports
  capacity=allocatable `amd.com/gpu: 2`** [S14]. `Allocate()` injects `/dev/kfd`
  + the allocated card/render nodes, **sets no ROCR/HIP_VISIBLE_DEVICES**
  [S13 plugin.go]; candidate sets are enumerated **sorted by nodeId ascending**
  (the APU-first pick that crash-looped charts/vllm on 2026-11-07 with zero HIP
  devices — repo-recorded evidence [S15]). No per-name allocation; no
  occupancy persistence across plugin restarts (in-process available-list only,
  19 restarts observed) — the guide's "Allocate() has NO occupancy check →
  Deployment strategy: Recreate" is directionally VERIFIED (mechanism read in
  source; Recreate is additionally required by the pinned-RAM double-process
  law already encoded in the lab's strata controller [EXPLORE §1b]).
  **Naming**: PR #246 *product* naming strategy (resources named from
  amdgpu.ids marketing names) is **merged 2026-10-19, shipped in plugin
  v1.31.0.12 (2026-11-06)** — the guide's "unverified" is stale; the lab's
  1.31.0.9 predates it. `AMD_GPU_DEVICE_COUNT` caps count — not re-verified
  this round (chart-values path 404'd), UNVERIFIABLE-Med.
- **iGPU hiding**: vfio-pci `ids=1002:1586,1002:1640` removes the 8060S from
  host amdgpu/KFD (Strix Halo wiki + Proxmox guides) [S17] — that would make
  `amd.com/gpu` = 1 = R9700-only, **but today the outer llama-swap pod holds
  `amd.com/gpu: 1` and it was given the 8060S to run the unified-vulkan GGUF
  models** [EXPLORE §3] — hiding the APU kills that serving class (the
  catalog's local llama-swap family). The lab's proven idiom instead is
  **privileged + hostPath /dev/kfd+render, no plugin claim, env-naming on host
  enumeration (0 = R9700)** — strata and vllm pods both do this today
  [S15][EXPLORE]; and llmkube shows the third way (DRA ResourceClaimTemplate
  selecting named R9700 devices) [S11]. Node has **no custom GPU label** —
  single-node k3s, selection is moot [S14].
- **k3s containerd ulimits**: the lab runtime is k3s v1.36.5 embedded containerd
  2.3.4-k3s1.36 [EXPLORE/S14]. Upstream `k3s.service` sets
  **`LimitNOFILE=1048576` (soft=hard)** — pods inherit ≥1M fds, no drop-in
  needed for nofile [S18]; the radiance-fd risk is exclusively the
  **llama-swap-child** path (spawner forces soft=1024 on children, #1255) and
  the repo already wraps strata children with `ulimit -n 524288` — same wrapper
  would serve a radiance child [EXPLORE §1b][S10]. `LimitMEMLOCK` is **not set**
  by the unit → inherited systemd default 8 MiB. Radiance needs memlock *only*
  for (a) the io_uring rings (L1T troubleshooting: "libavx: cannot make a ring
  → io_uring needs more locked memory"; llmkube: rings "count against
  RLIMIT_MEMLOCK (8 MiB) **per UID** — a dedicated runAsUser gets a fresh
  budget", which is why that pod needs **no drop-in** [S7][S11]; (b)
  host-backend/locked-huge-pages ngram copies, not applicable on cards [S3
  DOCKER.md]). Card-path pins are driver-locked user memory **not charged to
  the ulimit** [S3 DOCKER.md]. So the guide's "containerd LimitMEMLOCK=8MB →
  systemd drop-in (k3s.service.d)" is **CORRECTED to optional insurance**:
  precedent (llmkube; plus the lab's own strata pod pinning ~100+ GiB of arena
  with no drop-in — live RSS 73.9 GiB / working-set 109.05 GiB against its
  110Gi limit [S14]) shows 8 MiB +
  dedicated UID suffices; the drop-in path (k3s.service.d override) is valid
  if the plan prefers belt-and-suspenders — host-level, owner's lane.
- **Pod security**: the guide's non-privileged shape (supplementalGroups = host
  render/video GIDs, drop ALL + IPC_LOCK, seccomp unconfined, shm emptyDir)
  matches upstream `common.yaml` (devices kfd+dri, group_add render+video,
  ulimits memlock -1, seccomp unconfined with a shipped `seccomp-radiance.json`
  = Docker default + **io_uring + mbind/set_mempolicy**, healthcheck /health
  15m start, stop grace 60s, models ro) [S3 compose] — **plus two lab
  specifics**: this node's `/dev/kfd`+render are **group 486 mode 660** and a
  non-root container "cannot open /dev/kfd even under privileged" when runc
  drops caps on setuid — which is why strata/vllm run runAsUser 0 +
  privileged today [S15]. A non-privileged radiance pod MUST put the **kfd
  group GID (numeric, resolve on-target — the C04 gate EXPLORE deferred)** in
  supplementalGroups, not just render/video. IPC_LOCK: radiance compose does
  not require it (uses none); it matters only if the pod mlocks — keep as the
  guide drew it, harmless. seccomp: `Unconfined` or the shipped custom profile
  (RuntimeDefault **breaks the ngram disk tier + ROCm NUMA** — a hard gotcha
  the guide's "Unconfined" implies but doesn't explain [S3 common.yaml note]).
  hostPath `/srv/models` vs repo reality: lab models live on the existing
  **`llama-swap` 500 GiB RWO local-path PVC** (strata & vllm both mount it via
  `existingClaim`) — a radiance chart should reuse that claim, not a new
  hostPath, unless the guide's disk-tier-on-fast-NVMe need (≥5 GB/s O_DIRECT
  [guide checklist; engine disk tier requires O_DIRECT fs [S2 §4.3]) says
  otherwise: local-path storage lives on the node disk — verify speed
  (planning read, not research).
- **ReBAR / link facts**: not observable via the k8s API (no pod exec, no
  sysfs through MCP) — owner-provided OCuLink Gen4 x4 stands. Engine-side
  verification is built-in: the **startup report HARDWARE section prints BAR
  size, per-hop PCIe link speed/width with a "read at 90% busy" caveat,
  ttm.pages_limit, cwsr_enable, memlock limits, cgroup limits, swap usage**
  [S2 §7.1], and `/diagnostics` re-reads live — this is the acceptance-check
  tool for on-target bring-up (idle links park at Gen1; sample under load
  [S9][S19]). Guide host-checklist items cross-checked: ReBAR "size=32G both"
  (`lspci -d 1002:7551 'Region 0'`) ✓ [S3 RIG]; kernel: `iommu=pt` ✓,
  CWSR must be 1 (engine refuses otherwise) ✓ [S2 §1.1]; **ECC off recovers
  ~2 GiB VRAM/card** (`ras_enable=0`, mem_info 34,208,743,424 = 32,624 MiB —
  the receipt should show ~31.86 GiB usable — EXPLORE matches) [S3 RIG];
  swap/zram-off ✓ [S9 — `systemd.zram=0`, generator cannot be masked safely];
  amdgpu.runpm=0 — upstream instead keeps cards awake in its tune service
  (`power/control on`) ✓ equivalent; P2P kernel configs `HSA_AMD_P2P`/`PCI_P2PDMA`
  ✓ checked in RIG step 5 (`/proc/config.gz`); `DMABUF_MOVE_NOTIFY` — not in
  upstream docs, unverified; `pci=disable_acs_redir` — upstream uses
  `iommu=pt` and rocm-bandwidth-test checks instead, ACS-redirect handling not
  radiance-required (its P2P probe falls back automatically) [S2 §4.7][S3 RIG].
  HSA_OVERRIDE_GFX_VERSION not needed on gfx1201 ✓ consistent (native libr4d).
  "No HIP/ROCR_VISIBLE_DEVICES when the plugin injects nodes": the plugin
  injects no env at all [S13], so on the *plugin* path you must NOT rely on
  env ordering; on the *hostPath* path (lab idiom) env naming is exactly how
  strata targets the card — keep the lab's rule (host enumeration 0=R9700)
  [S15].

## RQ4 — SECOND-GPU (TP2) EXPANSION

Hardware path (PEX88048/88096 switch on the closed-ended x4 slot; two M.2
OCuLink links "Option M"; P2P via Strix root complex unverified):
- The Gen4-vs-Gen5 switch family split and product existence are community-
  corroborated: "88XXX chipsets are gen 4, 89XXX chipsets are gen five",
  PLX/PEX88048 x16→4×SFF-8654 boards, connectors matter [S19]; P2P through an
  external switch is **fabric-bound** ("R9700 to R9700 ~13.4 GB/s symmetric …
  bottlenecked by the external switch's P2P fabric, not the connection — a
  twice-as-wide link would still be fabric-bound") [S19]. The guide's precise
  "L1T 28.07 GB/s / doug.sh 54.7 GB/s aggregate" figures: **not located in any
  fetched post** — UNVERIFIABLE (low confidence in the numbers, medium in the
  direction: switch gives real P2P but under x4-host-link aggregate).
- "Both cards share one x4 uplink" with the PEX switch ✓ (upstream x4 port on
  the closed-ended slot; the switch's downstream cards contend on it) [guide +
  S19 product pages]. Option M (two M.2→OCuLink links doubles *host* bandwidth
  but P2P then crosses the root complex, "unverified"): Strix is Zen — the
  kernel's p2pdma permits AMD root complexes nearly unconditionally [S9], and
  radiance **probes per-pair at launch and falls back to host-memory mailboxes
  automatically** ("The results are the same bytes; a message crosses two
  links instead of one. On two R9700s on PCIe 4.0 that is **within run-to-run
  noise for decode at 1–4 streams, and 2–10% on a 23.6K-token prefill**")
  [S2 §4.7]. `--p2p off|on|auto` overrides. **So the "root-complex P2P
  unverified" risk is bounded by design for radiance**: worst case is the
  measured host-mailbox penalty, unlike the RCCL/hipIpc crash class the guide
  cites for vLLM — radiance uses no RCCL/hipIpc, so that crash doesn't apply
  (CORRECTED: keep as a vLLM-lineage footnote only; ROCm 7.1's
  `HSA_ENABLE_IPC_MODE_LEGACY` fragility is documented [S9]).
- Engine TP2 evidence (works on the class): Wilde's Z490 box has **no chipset
  P2P at all** and ran fn/q27 TP2 for days through host staging (his
  `note p2p-off` log) [S8][S9]; the x16+x4 asymmetric rig measured TP2 fn at
  ~2,450 tok/s prefill @55k with the stager at ~85% of the x4 link [S7];
  llmkube runs TP2 at **full 262144** with pool 8192 on a 62 GiB host [S11];
  jackal830's `--tp-wire wht6 …` config [S7]. TP2 flags from the guide
  (`--tp 2 --tp-wire wht6 --max-num-seqs 8 --max-model-len 200000
  --host-pool-mib 12288 --gpu-headroom-mib 96 --prefix-cache-mib 4096`
  (+spec 3, chunks 2048)) = **VERIFIED verbatim vs flashnext.yaml + fn HF card**
  except `--expert-vs-cache-ratio 0.82` (stale, RQ1). TP2 KV pool ~15.7 GiB
  (~60 KB/token; one 262k whale or ~4×64k) = VERIFIED-as-Wilde-measurement [S8].
- `amd.com/gpu: 2` with the plugin counting the 8060S: on *this* node a
  plugin-allocated 2-GPU claim today would take {8060S, R9700} (only two exist)
  — a mixed-rank TP2 on gfx1151+gfx1201 is **not a documented radiance mode**
  (libr4d collectives are gfx12; the multi-rank tests assume like cards
  [S1][S2 §4.7]) — so TP2 with the plugin *does* require hiding the APU or
  moving both cards off the plugin; with the lab's privileged/hostPath idiom +
  env naming, a second R9700 just extends the render list — but **re-enumeration
  law**: every `rocrVisibleDevices`/`ROCR_VISIBLE_DEVICES` index in the repo
  (strata strix="1", vllm "0", EXPLORE §1b/§2) shifts when a third GPU lands
  [EXPLORE §7]. Strix-Halo-specific: most Strix boards **cap an AMD dGPU on
  OCuLink/M.2 at ~120 W** (community wiki, S19) — two OCuLink R9700s may both
  be power-capped; xct measured "capped at the minimum 210 W is fine (<1% of
  decode)" only for slot-mounted cards [S16] — the 120 W cap, if it applies to
  the lab's board, is a decode-relevant unknown. Guide's §4.3 vfio-pci
  recommendation for a *headless* iGPU: mechanically ✓ [S17], but see RQ3's
  interdependency (the outer llama-swap's APU GGUF serving would die;
  catalog `-strix` fallback goes with it).

## RQ5 — OPERATIONAL + STRUCTURAL (child vs peer vs second controller)

**Image cadence/pinning**: ~38 tags in 5.4 weeks [S4]; renovate with the
`docker` datasource on Docker Hub tags is proven in two other cluster repos —
dsluo #2184 and Tanguille/cluster #6536 are **Renovate-generated**
`docker.io/stilldeadcode/radiance 1.16.0 ➔ 1.17.0` PRs (merged Nov 4 and
Nov 6) [S11 + api]. So the guide's "renovate tracks it; the lab pins" is
VERIFIED as feasible. **No ghcr mirror exists** (upstream publishes Docker
Hub only; woodpecker CI runs tests, publishing is the author's `docker/build.sh`
[S3 woodpecker, DOCKER.md]); the repo's own precedent would be a thin
re-export under `containers/` (strata/vllm law: `:main`+Always + tag→digest
ledger [EXPLORE §6]) vs digest-pinned upstream (llama-swap precedent) — a plan
decision; research note: tags CAN move (upstream rebuilt tags in place per
chart comment history [EXPLORE §6]), so whatever the shape, **record the digest
in the ledger**; note the index-vs-manifest digest distinction (RQ0) when
writing it.

**`.rad` "container file"**: VERIFIED — "A container holds everything the
server needs: the weights, the tokeniser, the chat template and any drafter"
[S1]; L1T: "single-file model packages with weights, config, and metadata
baked in"; download resumes (`curl -LC -`) [S5/S7]. `--model` takes a .rad
path, a plain checkpoint dir (served as shipped), or an HF repo id fetched via
`hfget.sh` — with **`--model-revision` for pinning weights to a tag/sha** ("a
deployment that must not restart onto weights nobody reviewed should name a
tag or a sha") [S2 §3.1/§4.11]. The lab staging pattern (vllm's setup init +
marker file) has an easier radiance equivalent: ship the .rad path on the
shared PVC; pin the HF revision in the ledger.

**q27 DFlash2 built into the pack**: VERIFIED [S5 q27 card; S8 "the DFlash2
drafter is compiled into the .rad pack — the depth flag doesn't own the
drafter"]. q27 speed profile (TP1 `--max-num-seqs 8 --max-model-len 200000
--kv-cache-dtype fp8` + `--prefix-cache-mib 4096`): card-verified TP1 fits one
32 GB card ("same flags otherwise") + 18.07 GiB weights/12.48 GiB KV receipt
[S5][S8]; the `--prefix-cache-mib 4096` rider is **Wilde's operational patch**,
not the card's ("add --prefix-cache-mib 4096 to the 27B service") [S8];
"200K cap / 262K boots, KV refuses past 12.46 GiB" VERIFIED as Wilde [S8].
The "116.0/93.5/122 aggregate" trio: **116.0 and 93.5 are Wilde's Gen4 n=4
follow-up averages** (64k/128k), 122 is the *creator card's* short-prompt
single-stream aggregate — guide conflated; both real, different rigs
(CORRECTED attribution). MTP "62–88% accepted" on flash-next TP1: VERIFIED as
the swift1.5 card's pre-upload smoke run ("arithmetic, a multi-step word
problem, a tool call, an image description and four concurrent requests all
answered correctly, with 62–88% of the MTP drafts accepted") [S5] — a functional
test, not a sustained benchmark; the guide self-labeled it as published recipe
(✓).

**Endpoints**: `/health`, `/v1/health`, `/ping` (GET+POST) are **liveness and
key-EXEMPT**; `/v1/models` exists (vLLM-shaped, `max_model_len` + `capabilities`),
`/metrics` Prometheus with the `vllm:` compat family; `/stats`, `/sessions`,
`/graph`, `/dashboard`, `/diagnostics`, `/server_info`, `/load`, `/version`,
llama-server native `/props` `/completion` `/tokenize` [S2 §5.1/§6.6].
llama-swap `checkEndpoint` default `/health` → **works unchanged against
radiance (200, no key)**; guide's startup-probe claim "/v1/models (30 min
allow)": llmkube actually probes **`/health`** at startup 180×10s (30 min) and
readiness `/health`; compose healthcheck = `/health` with 15m start_period
[S11][S3] — CORRECTED to `/health` (also required if `--api-key-env` is set,
since `/v1/models` is *not* key-exempt).
**Startup time**: first load reads ~66 GiB into VRAM+pinned pool (113.6 pack −
47.7 table served from disk under `disk`; matches TP2 receipt 21.9×2+24≈66)
[S7] — minutes-class on ≥5 GB/s local NVMe; L1T measured ~4 min over 0.3 GB/s
NFS; ngram `ram` adds +12–40 s copy [S2 §4.3]; q27 loads 18 GiB — sub-minute
plus KV carve. The lab's `healthCheckTimeout: 1800` (inner supervisor) /
`3600` (outer) comfortably covers it [EXPLORE §1].
**DNS-rebinding/allow-host**: without `--api-key`, machine-view routes
(`/diagnostics`, `DELETE /sessions`, LoRA, control-vector) require loopback
socket **and loopback Host**; peer-forwarded chat completions are unaffected;
`--allow-host box` exists if needed [S2 §6.6]. (The strata `*_ALLOWED_HOSTS`
law [EXPLORE gotcha 11] does NOT carry to radiance — different mechanism,
narrow guard. No new allow-list entries needed for a radiance peer… unless
running keyless and probing `/diagnostics` from off-box — flag for probes:
kubelet probes `/health` — exempt — fine.)
**Graceful stop**: "radiance is not a daemon; run it under a supervisor. It
finishes the step in flight and releases the cards on SIGTERM" (compose
`stop_grace_period: 60s`; `scripts/fnstop.sh` waits for exit) [S3 compose,
S2 §6.7]. k8s: terminationGracePeriodSeconds ≥ 60 + headroom; note strata's
420 s grace was sized for llama-swap child unloads — a peer radiance pod needs
only its own drain (~60–120 s).
**API key**: `--api-key` (Bearer/X-Api-Key) or `--api-key-env NAME` (preferred;
argv is world-readable) [S2 §6.6/§4.11]. Lab peers are keyless today (C-A
ruling): a keyless radiance pod on cluster DNS is consistent with that posture;
`apiKeys`/`${env.VAR}` config-load-failure law applies to llama-swap's own key,
unchanged.

**STRUCTURAL (the plan's question): peer vs second-controller vs child.**
Evidence:
1. **Child works** — #1255 user ran radiance 1.10 as a llama-swap child
   (`proxy: http://127.0.0.1:${PORT}`, `checkEndpoint: /health`,
   `useModelName`, ulimit wrapper), TP2 2×R9700 [S10]. With ONE card, the
   child pattern means fn↔q27 **swap** on the R9700 (like strata's matrix
   arenas): only one holds VRAM/RAM at a time; swap cost = full reload
   (~66 GiB fn, minutes; q27 fast) + the `unloadTimeout`/grace choreography +
   inherited-root io_uring memlock budget; `globalTTL: 0` + per-model ttl
   already encode lazy unloads today [EXPLORE §1b/§1c]. The lab's own RAM law
   comment ("llama-swap cannot evict across instances — nothing boots
   resident") is exactly the constraint radiance's 49 GiB pins sharpen.
2. **Peer is the proven production shape** — llmkube (single-model peer
   Deployment, `/opt/radiance/bin/radiance`, DRA claim, non-privileged, no
   swap) [S11]; upstream compose is one Deployment per model on the same port
   ("Every model listens on the same port and most use both cards, so run one
   at a time") [S1] — radiance *itself* plans per-model containers, not
   intra-process swapping. Peer = no reload, catalog rows stable, model id via
   `--served-model-name` (defaults to container name — set it to the catalog
   id!) [S2 §4.11]. Cost: fn-TP1 + q27-TP1 co-resident on ONE card is
   co-tenancy: radiance documents two-engines-one-cards carefully — the
   **deadlock case is two TP engines' collectives**, which TP1-on-one-card
   engines avoid (no cross-card spinners), but queues: "an R9700 has four
   compute queue slots and the two servers hold eight, so every decode step
   waits for a switch", `--weight-prefetch off` for the second engine,
   second engine's headroom claimed by the first
   (`--gpu-memory-mib` to carve, §4.3/§8) [S2 §8]. Wilde's box ran *desktop +
   engine* co-tenancy fine; two full engines he sized to one at a time [S8].
3. **Second-controller (cf-77 shape)**: strata is a second *controller* of the
   llama-swap Application with its own pod but supervised children — radiance
   would keep that pod shape without needing the supervisor: a controller
   running radiance directly + a `peers.radiance` block is *effectively the
   peer shape inside the existing Application* (chart-side, like strata's
   enable-set) — plausible middle option: own Application vs
   llama-swap-chart-controller is an ArgoCd/GitOps call, the runtime shape is
   identical (one container, fixed port, service, peer block). The EXPLORE's
   "tension" resolves: the card's "NEW chart" and the peer wiring both land
   fine; the *strata second-controller pattern itself* is the closest precedent
   minus the supervisor.
**Finding**: peer/own-pod is supported by every production witness [S11][S7]
and avoids #1255's whole fd/limit class; the child pattern buys single-card
swap (one model's pins at a time) at the cost of minutes-long fn reloads and
repo-documented eviction law — it is the shape *only if* the lab refuses to
co-provision fn+q27 VRAM concurrently. Co-tenancy math says q27 (18+KV) + fn
TP1 *cannot* share 32 GiB — fn-tp1 alone consumes ~28–30 GiB of card in the
receipts [S3 compose header, S8] → so with ONE card the honest choices are:
**q27 peer always-on + fn as swap-child (or manual compose), or fn peer
always-on + q27 child, or wait for card 2** — planning/owner call; research
flags that *two peer radiance pods on one GPU is NOT feasible for fn+q27*
(capacity), and that fn-tp1-ram profile + q27 co-residency blows the RAM
budget too (105–110 pinned + 8.5) [RQ1].

## Guide corrections (claim → verdict → corrected fact)

| claim (condensed guide) | verdict | corrected / confirmed |
|---|---|---|
| "Latest Radiance v1.17.0 (2026-11-04)" | VERIFIED | [S4][S6]; no 1.18 as of Nov 11 |
| "38 tags in ~5 weeks; radiance releases weekly" | CORRECTED | 38 git tags / 39 hub tags, Oct 4→Nov 4 = 5.4 wks → **1–2/week** [S4][S6] |
| "main moved past 1.17.0 (--prefill-interleave auto:1, 2026-11-05)" | VERIFIED | commit a5830463 2026-11-05; flag table in v1.17.0 still says default 0 [S1][S2] |
| pin `1.17.0@sha256:6fb0e99b…` / `1.16.0@sha256:b1017ce0…` | VERIFIED (pin-shape nuance) | 6fb0e99b = amd64 *image manifest*; the tag's *index* digest is c2acbaa3 — pick one spelling and ledger it; llmkube pins 6fb0e99b successfully [S4][S11] |
| images built for gfx1201/gfx11-generic/gfx1151; host needs amdgpu w/ ROCm 10.1, no ROCm | VERIFIED | [S1][S3][S16] |
| "ReBAR required … without it every dispatch reads over link" | VERIFIED + quantified | args-in-pinned-host-mem costs 0.4–1.8% decode at TP1/TP2 **but P2P needs the large BAR** — critical only for TP2 [S2 §1.1] |
| pin cap = RAM − RAM/64 − 1.5 GiB; pool is locked user memory; ttm.pages_limit doesn't count it | VERIFIED | README verbatim [S1]; ≈120.6 GiB on the lab box |
| fn pack 113.6 GiB, ~47.7 GiB n-gram, ~66 GiB loaded, 10 bf16 experts, MTP 3, 262144/200K | VERIFIED | exact bytes/sha [S5]; "66" = pack minus table [S7 arithmetic] |
| fn-tp1 recipe "--tp 1 --max-model-len 32768 --max-num-seqs 4 --host-pool-mib 38600 --weights-disk-tier … --max-num-batched-tokens 2048 --host 0.0.0.0 --api-key $KEY" | CORRECTED | that is the **swift1.5 card** row; v1.17.0's shipped `flashnext-tp1.yaml` = **200K ctx / pool 43000 / chunks 4096 / checkpoint-interval 4096 / prefix-cache-mib 4096 / --api-key-env / --host ::**; guide mixed the two |
| "62–88% MTP drafts accepted on one R9700, four concurrent" | VERIFIED | swift card smoke run, not sustained bench [S5] |
| "64 GiB machine serves flashnext-tp1.yaml with 49 GiB pinned" | VERIFIED | README §4.3 example [S1] (compose: "wants a host with 64 GB") |
| q27 profile + "116.0 @64K / 93.5 @128K / 122 aggregate", "262K boots, KV refuses past 12.46 GiB" | CORRECTED-attribution | 116.0/93.5 & 12.46 = **Wilde Gen4 measurements**; 122 = creator card aggregate [S5][S8]; prefix-cache-mib 4096 rider is Wilde's patch [S8] |
| fn TP2 flags incl. `--expert-vs-cache-ratio 0.82` | PARTLY STALE | ratio flag **not in v1.17.0** (engine-derived split; exists only on the stale HF card) [S2 §4.3/§4.11]; rest verbatim ✓ [S3][S5] |
| "decode estimate 30–80 tok/s single-stream on fn-tp1 (UNMEASURED)" | SUPERSEDED | measured on x16-class TP1 receipts: 29.0/28.0 ms step @1seq ≈ **35 tok/s** (prefetch off/on), 101.3/95.3 ms @4seq [S2 §4.3]; on x4 the 454-tok/s prefill number is the real pain [S7] |
| Gen4 x4 ~6.3 GB/s real; TP1 fn "few hundred tok/s prefill" | VERIFIED-by-measurement | 7.0–7.2 GB/s; 454 tok/s @55k; 15 MB/token link traffic explains it [S7 p5]; 27B TP1 x4 −5% only [S7 p5] |
| Strix LPDDR5X ~256 GB/s so host RAM isn't the limit | VERIFIED | 230 GB/s cold-read measured [S3 STRIX doc §3/§7.11] |
| fn-tp1-ram ~95–100 GiB, 108Gi limit "only if sole large tenant"; ~10% delta via bigcherry #512 | VERIFIED + WARNING | ~10% ✓ [S12] ("about 10%"); L1T voices say ~3% — use 3–10%; **demotion-burst pinned OOM** is the trap [S9]; 60/108Gi limits vs the engine's 4 GiB-free-under-cgroup refusal [S2 §4.3, S11] |
| amd-gpu chart "0.22.0"; Allocate() has NO occupancy check → Recreate | VERIFIED live | chart 0.22.0 appVersion 1.31.0.9 on node, amd.com/gpu:2 counting the APU [S13][S14]; in-process availability only, plugin restarted 19× [S14] |
| "plugin after kernel 7.1.3 silently stopped advertising amd.com/gpu (t1m.me)" | UNVERIFIABLE | post not locatable (searched); on THIS node (kernel 7.3.0-1-default, plugin 1.31.0.9) advertising is live — and plugin.go's empty-bucket guard shows stale-capacity IS a real failure family across restarts [S13]; treat as cautionary, not a fact |
| "naming strategy single/mixed don't produce per-model names; product naming PR #246 unverified; AMD_GPU_DEVICE_COUNT caps count not choice; ROCR_VISIBLE_DEVICES unreliable at gpu:1" | CORRECTED | `product` strategy **merged 2026-10-19**, first in **v1.31.0.12** (2026-11-06) — a chart/plugin bump gives per-product resources (amd.com/Radeon-AI-PRO-R9700)[S13]; #246 no longer "unverified"; ROCR-env unreliability = plugin injects no env + nodeId-ascending pick — the lab's own crash record [S15]; AMD_GPU_DEVICE_COUNT not re-verified (chart values path 404) |
| iGPU hide via vfio-pci 1002:1586 recommended | VERIFIED mechanism, INTERDEPENDENT | works [S17] but kills the outer llama-swap's 8060S GGUF allocation (EXPLORE §3: that pod *has* the APU); lab idiom (privileged hostPath + env naming) sidesteps hiding entirely |
| pod: supplementalGroups render/video, drop ALL + IPC_LOCK, seccomp Unconfined, Guaranteed, /dev/shm 2Gi, hostPath models ro, startup /v1/models 30min, liveness tcpSocket | CORRECTED | upstream compose posture confirmed (group_add render+video, memlock -1, seccomp unconfined **because stock profile refuses io_uring + NUMA calls**, healthcheck /health 15m) [S3]; lab deltas: kfd group 486 must be in supplementalGroups for non-root [S15]; shm: L1T runs `--shm-size 32g --ipc host`, upstream compose ships none (2Gi figure looks lifted from the strata DOCKER.md precedent [EXPLORE]); startup probe → `/health` (auth-exempt, proven in llmkube) not `/v1/models`; models live on the existing `llama-swap` 500Gi PVC, not a new hostPath [EXPLORE §4] |
| containerd LimitMEMLOCK=8MB → systemd drop-in; nofile ≥1M + entrypoint ulimit raise (llama-swap#1255) | CORRECTED | k3s unit already sets LimitNOFILE=1048576 — no pod-side fd problem; #1255 is the **child** path only (repo's ulimit wrapper idiom covers it) [S18][S10]; memlock: card-path pins don't count against the ulimit; only io_uring rings do → dedicated-UID precedent (llmkube, no drop-in) or optional k3s.service.d drop-in [S11][S3 DOCKER.md][S7] |
| radiance cgroup check warns + refuses unless 4 GiB free (dsluo PR#2070/#2127) | VERIFIED | `--host-headroom-mib` (4096) enforced across cgroups; llmkube PRs cite source + the observed "cgroup-limit" warning [S2 §4.3][S11] |
| API surface (OpenAI + Responses + Anthropic Messages + llama-server native; dashboard /; /stats step-time; --api-key→Bearer) | VERIFIED | endpoint table [S2 §5.1]; plus /metrics /sessions /diagnostics /load /props /server_info /health /ping |
| "deploy/grafana/radiance.json ships per tag; scrape path /metrics assumed" | VERIFIED | folder exists @v1.17.0; **/metrics confirmed** Prometheus text, vllm-compat family [S2 §6.3][S3] |
| TP2 "real P2P via PEX switch: L1T 28.07 GB/s; doug.sh 54.7 GB/s aggregate" | UNVERIFIABLE | figures not located in fetched posts; direction corroborated (switch P2P works but is fabric-bound, ~13.4 GB/s symmetric class [S19]); P2P-crash-avoidance claim is an RCCL/vLLM concern — radiance has no RCCL and auto-falls-back to host mailboxes (measured: decode noise, prefill −2–10%) [S2 §4.7] |
| TP2 "single-stream decode 125–160 tok/s (shared x4 → low end); aggregate 252 (8 lanes 64K); spec off 252→278" | VERIFIED | creator card: ~15 ms/step ≈160; Wilde Gen4: 142–146 follow-up, 252→278 table, per-user 53 at 8 lanes [S5][S8]; fn HF-card quality/step figures ✓ |
| host checklist (ReBAR 32G, Above-4G, iGPU carve-out min, iommu=pt, runpm=0, swap/zram off, pin ceiling ≈120.6, perf profile, SELinux container_file_t, Gen4 NVMe ≥5 GB/s dd iflag=direct, 210–250W cap) | MOSTLY VERIFIED | RIG doc confirms ReBAR/Above-4G/CSM-off, iommu=pt, ECC-off (+2 GiB VRAM), 210 W ≤1% decode, power-caveats; zram: `systemd.zram=0` is the real lever (masking generator units re-runs it!) [S3][S9]; O_DIRECT requirement for disk tier ✓ [S2 §4.3]; SELinux label item = openSUSE-Tumbleweed-specific, plausible, not re-verified (low); **add from evidence**: `amdgpu.cwsr_enable=1` is a hard startup requirement [S2 §1.1]; kernel 7.3.3 `mem_info_vram_vis_total` regression (lab at 7.3.0 — check before adopting a 7.3.3+ Tumbleweed snapshot) [S9] |
| "radiance serve" / exec'd process binds ${PORT} | CORRECTED | no `serve` verb; `--port` flag ✓ default 8000, ${PORT} macro fine in child mode (#1255 proves it) [S1][S10] |
| "priority likely unsupported; preemption maybe" | CORRECTED — both supported | priority queue + preemption-by-recompute, request `priority` field (default 0, **higher wins**) + `--preempt-wait-ms` + preempt metrics [S2][S3 spec/scheduler.h/oai.h] |
| flash-next pack "MTP depth 3" served via `--num-speculative-tokens 3` | VERIFIED | head lives in the container; `--draft-model` is an error (merged at convert) [S2 §4.6] |
| (new, load-bearing) vLLM→radiance priority polarity | FINDING | lab's urgent=1/low=9 must flip for radiance (urgent=high number) or urgent traffic becomes the preemption victims [S2 §4.11, scheduler.h] |

## Serving envelope (numbers the plan can pin)

Hardware base: 1× R9700 gfx1201 (32,624 MiB VRAM ECC-off, ~31.86 GiB usable to
the receipt), OCuLink **Gen4 x4** ≈ 7.0–7.2 GB/s measured class [S7]; Strix
Halo iGPU 8060S (gfx1151, unified, 230 GB/s host read measured [S3]); host
~124 GiB (allocatable 125.08 GiB [S14]); pinned cap ≈ **120.6 GiB** [S1];
engine headroom rule: ≥4 GiB free under cgroup for RAM placements [S2 §4.3].

Per-token VRAM KV cost (fp8): the engine's own worked example = 7.32 KiB/token
(kv_attn 26.00 + kv_qsa_bkey 3.25 per 4-token block) + per-sequence delta-net
state 54 MiB ×2 copies under speculation + full-context block tables (§4.4)
[S2]; field receipts ran 30–60 KiB/token effective [S8, S16] — **pin to the
startup receipt, not either constant** ("kv: the pool backs N% … M full-length
sessions"; "To size it, multiply what a token costs across ALL paged groups
(the startup log prints it)").

Profiles (all VERIFIED published recipes):
- **q27 speed leg, TP1 one card**: pack 18.05 GiB; receipt ~18.07 GiB weights
  + ~12.48 GiB KV on 32 GiB card [S8]; flags `--tp 1 --max-model-len 200000
  --kv-cache-dtype fp8 --max-num-seqs 8 [--prefix-cache-mib 4096]` [S5][S8];
  host RAM ≈ 8.5 GiB (7.89 pinned) [S8]; decode 122 t/s aggregate card /
  116.0 (64k) / 93.5 (128k) Wilde; 8-lane aggregate 106 at 64k / 288 short-
  prompt [S8]; link-immune (x4 −5% pp) [S7]. **8 sessions: this is the
  session-capable lane** (admission ceiling = 8×max-num-seqs queued → 429).
- **fn quality leg, TP1**: v1.17.0 recipe pool **43000** (guide's 38600 = old
  card), pins ≈49 GiB, cache backs **301K tokens ≈ 1.5×200K session at 4
  seqs** [S3]; decode ~28 ms single-stream (~35 t/s with ~2.4 accepted →
  ~85 t/s effective is NOT claimed — the 28 ms is the step, ≈35 tok/s
  without spec / spec gives 1.4–3.2× → ballpark 50–90; treat as receipt
  item) [S2 §4.3]; prefill on x4 ≈ **450–600 tok/s @55k** (measured class,
  chunk 4096 ≈ 2× chunk 2048) [S7][S3]; `--max-num-seqs 8` raises
  state+tables ~+0.9 GiB and shrinks per-session backing — measure.
  8 concurrent long sessions on TP1 require **`--kv-resident 32768`**
  (QSA→RAM, host copy ≈ 8×max-model-len×~12 KiB ≈ **~19 GiB @200K**, prefix
  tier forced off) [S2 §4.4.1] — RAM-fits on 124 GiB *only as sole large
  tenant*; the documented TP1 refusal "2×262k host copy does not fit beside
  the weights" is on the reference rig's host, not an absolute law — verify
  on-target.
- **fn-tp1-ram variant**: ngram `ram` (+47.7) → total pins ≈ 100–110 GiB +
  demotion burst; ≤10% faster [S12]; only with everything else gone;
  **Wilde's pinned-demote OOM** shows how it dies [S9].
- **fn TP2 (second R9700)**: compose recipe (pool 12288/rank, wht6, 200K, 8
  seqs, prefix 4096) [S3]; creator rig ~160 t/s 1-stream, ~6.4K pp; Wilde
  Gen4-class: 142–146 follow-up, 2,816–3,552 pp, 8×64k = 252 agg (278 spec
  off), pool ~15.7 GiB ≈ 1×262k or 4×64k [S5][S8]; llmkube runs 262144 ctx on
  a 62 GiB host (pool 8192) [S11]; host staging costs decode noise / prefill
  −2–10% where P2P is absent [S2 §4.7].
- **q27 TP2**: 204 aggregate / 438 c4 card; Wilde 164.8/158.5 follow-up, full
  262144 fits (20.04 GiB KV/card, ~100 MiB spare) [S5][S8].

Catalog/matrix anchors (unchanged law): peer models stay out of the outer
matrix; `peers.radiance.models` lists ids explicitly, NO `/v1` suffix on
proxy URL, timeouts 1800/30 [EXPLORE §1a]; served ids via
`--served-model-name` [S2]; golden recapture + evidence file + M-arm re-pins
carry over (EXPLORE §5/§12 test obligations).

## Structural options (RQ5 decision input)

A. **Own chart + peer pod (like vllm today)** — every production witness
   (llmkube, Wilde compose, upstream compose is per-model containers). No
   swap; each model owns a fixed port/service; ids stable for the catalog.
   Single card forces fn-or-q27 resident, not both at TP1 scale (VRAM), so
   this option pairs naturally with "q27 peer always-on; fn on card 2 later"
   or with fn-as-child. Non-privileged shape needs the kfd-GID + io_uring
   memlock/UID handling solved (all precedented [S11][S15]).
B. **llama-swap second controller, radiance WITHOUT supervisor** — same pod
   shape as A but inside charts/llama-swap as an `app-template` controller
   (the cf-77 consolidation idiom); peer block identical. Buys zero runtime
   difference; it's a GitOps-packaging choice (one more Application vs one
   more controller — the card's "NEW chart" wording + EXPLORE tension is
   this fork, an owner/plan decision, not a capability question).
C. **llama-swap child (like strata today)** — enables fn↔q27 swap on one
   card; verified feasible (#1255 + config; checkEndpoint /health works;
   --host 127.0.0.1 --port ${PORT} + proxy:) [S10]. Costs: fn reload minutes
   on every swap-back (66 GiB read; the lab's own "swap reclaims VRAM"
   motivation), ttl/unload choreography (420 s grace law), io_uring memlock
   under the pod's root UID, `--max-queued-requests`/429 during loads, and
   the RAM profile swings 49↔8.5 GiB per swap (cgroup limit must cover the
   max). This is the *only* shape where one card serves both legs
   opportunistically.
D. (future) Two pods co-resident on one card (fn TP1 + q27 TP1): ruled out by
   capacity (fn ~28–30 GiB of the 31.86 GiB usable) [S3/S8] — do not plan it.

## Contradictions & confidence notes

- KV per-token cost: doc example 7.32 KiB vs field 30–60 KiB (different group
  counting / build eras). Resolved operationally: receipts. (H that receipts
  are authoritative — doc says so repeatedly.)
- ngram ram-vs-disk delta: 10% (bigcherry) vs ~3% (L1T voices). Use "≤10%,
  measure" (M).
- fn-tp1 decode: doc step-time numbers (creator, x16+) vs no published speed
  on x4 TP1 for decode specifically (prefill is measured). Single-stream
  decode should be near link-insensitive (10 experts/step × 1.245 MiB ≈ 12.5
  MB/token → ~1.8 ms extra @7 GB/s — consistent with "30–80" band's upper
  half). (M)
- Wilde's OOM story applies to a 62 GiB box; the lab's 124 GiB is a wider
  margin but the mechanism (pinned demotion burst, zram generator) is
  identical — carry as host-prep checklist items with the exact levers
  (`systemd.zram=0`, tier sizing ≥ burst, `--prefix-cache-mib 0` as the
  escape hatch). (H mechanism / M lab-specific sizing)
- "radiance = renamed Strata" hypothesis (EXPLORE): **refuted** — distinct
  repos/authors; radiance replaces strata only as serving substrate [S7][S20].
- Perspective check (storm peer-review): the strongest "skeptic" evidence
  against the whole card plan is Wilde's two posts — a Gen4/DDR4 box is where
  the guide's numbers *come from*, and the same author's conclusions were
  "the dense 27B is my daily driver on this board; the MoE models are kept
  for when the board or the RAM catches up" [S8]. The lab's fn-quality-leg
  expectations must survive that quote. Nobody in the fetched corpus serves
  fn-TP1-×-8-long-sessions on one R9700 — the envelope above is the best
  available triangulation.

## Adjacent (not in scope, recorded because cheap)

- radiance 1.17.0 added **IQR-V4** 27B packs: "the IQR kernels now decode
  faster than the MXFP4 checkpoint" (IQ4R-L-V4 ≈ 24% below official FP8-KL at
  55% size) [S6] — a candidate replacement pack for the speed leg post-cutover.
- `--model` accepts HF repo ids with `--model-revision` sha-pin [S2] — could
  replace the vllm chart's staging-init pattern entirely.
- `/v1/systemone`, `/v1/videos`, speech, images — radiance serves far more
  than the lab needs; vision (`--mm-max-patches` default 16384) is ON for both
  packs (matches the catalog's current text-only honesty marker D38 — decide
  whether radiance rows can advertise `in: [text, image]` honestly; llmkube
  ships vision [S11][S5]).
- The engine refuses startup on unsupported configs (cwsr=0 etc.) and prints
  the STARTUP REPORT on failure — the repo's exec-form boot-guard idiom maps
  onto it naturally (loud-fail at container start) [S2 §1.1/§7.1].
- k3s node is unschedulable-role-free: all workloads run on the control-plane
  node; radiance needs no special scheduling [S14].

## Open questions (genuinely unresolved — for coord/human)

1. **Polarity of the lab's priority table on radiance** — flip the catalog/
   peer values (urgent→high) or run flat-FIFO (no priority set, default 0
   everywhere) until the four-class table is re-specified? Owner call.
2. **Structure A vs B vs C** (own chart/Application vs llama-swap controller
   vs child-swap): research says all three *work*; the single-card fn↔q27
   trade (swap-with-minutes-of-reload vs q27-resident-and-fn-waiting) is an
   owner priorities call, not a capability gap.
3. **Lab-specific receipt unknowns** (need one on-target run, not more web):
   the flash-next TP1 startup receipt on THIS box (pool tokens, "M full-length
   sessions" line, `elastic` line, measured per-token cost) and whether
   `--kv-resident 32768` + `--max-num-seqs 8` + 200K ctx starts (the doc's
   TP1 refusal was on a smaller host); x4-prefill actual (expect ~450–600
   tok/s @55k, chunk 4096).
4. **kfd/render GID numbers + io_uring memlock posture** on the lab node for a
   non-privileged pod (C04 runbook still deferred; dsluo's dedicated-UID trick
   vs the repo's privileged idiom) — on-target `getent group`, `ls -l
   /dev/kfd`, mode check.
5. Whether the runner-model literal + catalog route strings (AGENTS.md, loops,
   pipeline-models tables) move with this card (owner-ruling-owned; EXPLORE
   open-question carried unchanged).
6. Who zeroed `gpu-ai-vllm` and whether disable should pin `replicas: 0` —
   coord/owner (EXPLORE), unaffected by research.
7. t1m.me device-plugin/kernel 7.1.3 claim: could not be located; if the owner
   still has the citation, it's worth pinning — else drop it from the plan's
   risk list (live node disproves it at 7.3.0).

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md]
commands_run: [repo reads (EXPLORE.md, charts/vllm values, containers/vllm-radiance-mxfp4 Dockerfile+README) => pass; Codeberg API: repo/tags/contents/raw docs (GUIDE/TOOLS/DOCKER/TP3/PREPARING_YOUR_RIG/STRIX_HALOD/spec/compose) @v1.17.0 => pass; docker.io hub tags API (39 tags, digests) => pass; HF models API ×3 repos + raw cards => pass; radiance.stilldeadco.de changelog => pass; github api: dsluo 2032/2070/2127/2184 (+ llmkube flashnext.yaml raw), bigcherry 512, Tanguille 6536, ROCm/k8s-device-plugin (plugin.go/naming.go/alloc.go/releases/helm index), mostlygeek/llama-swap 1255, Niko1221/Strata => pass; websearch ×5 (identity, Gen4 ladder, x4 ladder, k3s unit, 1002:1586) + webfetch ×6 => pass; readonly-ai-gpu-kubernetes: pods_list (selector), pods_get, pods_log (device plugin), resources_get Node, nodes_stats_summary => pass]
deviations: storm fan-out ran inline (no subagent harness in this session; per skill fallback) — all five lenses (engine-docs, k8s-practitioner, benchmark-field-report, device-plugin, repo-grounding) were interviewed against live fetches; intermediates kept in /tmp/opencode/radiance-research (outside the repo) to honor the write-RESEARCH.md-only constraint
friction: L1T forum HTML is JS-only — thread JSON API (/t/257789.json) is the working shape; Codeberg raw web path 404s — API /raw/{file}?ref=v1.17.0 with v-prefixed git tags (hub tags unprefixed) is the working shape; HF file blobs need /repo/tree?blobs=true; amd-gpu chart values.yaml 404 at guessed paths (chart detail left to plan); wildetech 404 on guessed post URL — real path is /blog/2026-11-08/what-a-gen4-board-costs…
open_questions: [priority polarity flip vs FIFO-until-reclass (owner); structure A-vs-B-vs-C single-card trade (owner); on-target TP1 receipts incl. --kv-resident start-up refusal test at 8×200K, x4 prefill actuals, kfd GID/memlock posture for non-privileged pods (one on-target run closes); t1m.me plugin/kernel claim unlocatable; who-zeroed-vllm + runner-literal scope carried from EXPLORE unchanged]
next_suggested: agent-plan reads RESEARCH.md §TLDR + Serving envelope + Guide corrections + Structural options; the plan question round should put the polarity flip and the A/B/C single-card structure to the owner with the fn-tp1 prefill measurement (≈450–600 tok/s @55k on x4) as the framing fact

## R6 — Per-device GPU resource naming (owner Q9 round)

Owner ask: apu and R9700 get **different resource names**; the APU stays assigned to
llama-swap; radiance deterministically requests the R9700 — no vfio hiding.
Round R6 reads the plugin source at released tags, the lab live, the repo GitOps
plumbing, and two production witnesses (dsluo/homelab, an R9700 field report).
Every claim cites [R6-S#] (accessed 2026-11-11). Verdicts: VERIFIED / CORRECTED /
UNVERIFIABLE + confidence.

### R6-TLDR (fold into the plan)

Per-device resource names are **supported today by the shipped plugin binary** —
`-resource_naming_strategy=product` (PR #246, merged 2026-10-19, first release
v1.31.0.12, 2026-11-06) advertises every GPU under a sanitized marketing name from the
`amdgpu.ids` table **baked into the image**, so on THIS node the kubelet pools become
`amd.com/gpu-ai-pro-r9700: 1` (7551/C0) and `amd.com/gpu-8060s: 1` (1586/C1·C3·C6·D1) —
computed by porting the naming code and running it against the vendored table (passes
upstream's own test fixtures) [R6-S1..S5]. The earlier RESEARCH name shape
`amd.com/Radeon-AI-PRO-R9700` was wrong (sanitizer lowercases, drops vendor/category
words, prefixes `gpu-`). **But no released amd-gpu Helm chart can turn the flag on**:
chart 0.22.0 (still master, still index-latest) has no args/command hook at all; the
upstream fix is a stale open PR #122 [R6-S6,S7]. So option 1 = vendor the chart in-repo
(the appset machinery renders internal charts from `charts/` with values fully under
GitOps) + `dp.image.tag: 1.31.0.12` + args; ship `amd.com/gpu-ai-pro-r9700: 1` in
charts/radiance and flip charts/llama-swap's `amd.com/gpu: 1` to `amd.com/gpu-8060s: 1`
in the SAME sync wave (after the flip the old name is GONE from node status — a
llama-swap pod rescheduled before its flip lands stays Pending). Strong alternative:
ROCm's **k8s-gpu-dra-driver v1.0.1** (DRA is GA-stable on the lab's k3s v1.36.5) —
ResourceClaimTemplate CEL-selects the R9700 by `deviceID == "0x7551"` with ZERO touch to
llama-swap or the plugin; production witnesses run exactly this on this exact card, one
on **k3s v1.36.6 with non-root pods receiving /dev/kfd+render via CDI** [R6-S8,S9,S10],
at the cost of a second GPU subsystem and one open reboot-CDI bug (mitigated by the
dsluo values: persistent `cdi.dynamicPath`) [R6-S11]. Two-DaemonSet device filtering:
DEAD (no device-selection surface exists in the source). Fallback trap on option 1: a
card whose sysfs device+revision pair misses the vendored table lands under bare
`amd.com/gpu` — on-target revision receipts + a post-flip node-status gate are mandatory
(C06 step 0).

### R6-Q1 — THE PLUGIN'S CAPABILITY (VERIFIED from source at the released tag)

**Strategy surface** [R6-S1][R6-S2][R6-S3]:
- `cmd/k8s-device-plugin/main.go @ v1.31.0.12` reads exactly two flags: `-pulse` and
  `-resource_naming_strategy` (default `single`; accepts `single|mixed|product`).
  **No env var and no config file sets the strategy** in the .12 binary. (`docs/`
  @ the same tag documents `AMD_GPU_DEVICE_COUNT` + `CONFIG_FILE_PATH`; the .12
  main.go/plugin.go/amdgpu.go implement neither — docs lead code. For our decision the
  distinction is moot: a *count* cap could never *choose* which card.)
- `internal/pkg/naming/` **does not exist at v1.31.0.11 (404) and exists at v1.31.0.12**
  — confirms "product first shipped in 1.31.0.12" (release published
  2026-11-06T17:55:49Z; PR #246 merged 2026-10-19T19:21:59Z, title
  "feat: add `product` resource naming strategy", closes #128) [R6-S2][R6-S3].

**What `product` produces on a heterogeneous CONSUMER node (the exact question):**
- `ResourceName(device, StrategyProduct)` = `ProductIndex.Name(deviceID, revisionID)` —
  the **marketing name from the table**, not a partition style. Non-partitionable cards
  simply get no style suffix (`partitionStyle()` returns "" when
  `current_compute_partition`/`current_memory_partition` sysfs files are absent — true
  for gfx1201/gfx1151; the docs' own example shows MI210 → `amd.com/gpu-mi210`)
  [R6-S1][R6-S4]. **The earlier round's "reported under amd.com/gpu regardless" verdict
  applied to `single`/`mixed` ONLY and does NOT carry over to `product`** — the PR body
  states the purpose verbatim: "`amd.com/gpu` cannot express which product a workload
  got … per-product quota and scheduling [impossible]", aimed at "clusters whose nodes
  hold more than one GPU product" [R6-S3][R6-S4].
- **Name formula** (`naming.go`+`products.go` @.12): read PCI `device`+`revision` attrs
  from `/sys/module/amdgpu/drivers/pci:amdgpu/<bdf>/` (normalized `0x74a1`→`74A1`),
  look the pair up in `/usr/share/libdrm/amdgpu.ids` — **which the Dockerfile bakes into
  the image** (`COPY … cmd/k8s-node-labeller/amdgpu.ids /usr/share/libdrm/amdgpu.ids`,
  with the comment "-resource_naming_strategy=product resolves product names from this
  table") — then lowercase, replace non-`[a-z0-9.-]` with `-`, drop filler words
  `{amd, ati, instinct, radeon, graphics, series}` (note: `pro` and `rx` are
  *deliberately* kept), prefix `gpu-`, collapse `--`, truncate at 63 (after `amd.com/`)
  without dangling separators. Unknown pair → bare `gpu`. Collision (two products
  shorten alike) → both fall back to `qualify()` (category words kept) [R6-S1][R6-S5].
- **Computed for THIS node** (faithful JS port of the two files run against the vendored
  752-row table; the port reproduces upstream's fixture expectations — MI300X→
  `gpu-mi300x`, MI300X-VF→`gpu-mi300x-vf`, MI210→`gpu-mi210`, the 540/540-Series
  collision pair, and unknown-revision→`""` — all pass) [R6-S5]:
  - R9700 (`7551, C0, AMD Radeon AI PRO R9700`) → **`amd.com/gpu-ai-pro-r9700`** (unique
    claim, no collision; the R9700S row at C1→`gpu-ai-pro-r9700s` stays distinct).
  - APU (`1586`, revisions C1/C3/C6/D1 → "AMD Radeon 8060S Graphics") →
    **`amd.com/gpu-8060s`**. (Same row family yields `gpu-8050s` on C2/C4/D2/D4 — the
    table keys on revision, so the live sysfs revision decides; see the fallback trap.)
  - `amd.com/gpu` **disappears** (both devices bucket under product names; nothing
    falls to the default bucket) — node advertises exactly the two names, 1 each.
  - Earlier name-shape correction: not `amd.com/Radeon-AI-PRO-R9700` — the sanitizer
    lowercases, drops "Radeon", prefixes `gpu-` [R6-S5].
- **Allocation architecture under product** [R6-S1]: the binary runs kubevirt's
  device-plugin-manager with the lister's `Discover` publishing the computed name list;
  dpm instantiates **one plugin per name**, each `ListAndWatch` reporting only its own
  bucket (`bucketDevices` groups by `ResourceName`), each `Allocate` injecting `/dev/kfd`
  + the allocated card/render. So per-name kubelet pools → a pod requesting
  `amd.com/gpu-ai-pro-r9700: 1` can only ever receive the R9700. nodeId-ascending
  APU-first ordering becomes irrelevant for cross-card choice (it only picks *within* a
  bucket). Determinism: **VERIFIED by source, HIGH confidence**; the plan's Q9 mis-
  allocation class is eliminated, not gated.
- PR #246 design note worth keeping: naming reads sysfs **directly, not through
  libdrm**, because the device-plugin DaemonSet mounts only `/sys` (no `/dev/dri`) —
  every lookup would fail via the libdrm path in the shipped image [R6-S3].

### R6-Q2 — THE LAB'S CURRENT INSTALL + THE EXACT UPGRADE PATH (CORRECTED vs the PR-page optimism)

- **In-repo owner**: `services/gpu-ai/prod/values.yaml:40-44` — `charts.amd-gpu:
  {version: 0.22.0, repository: https://rocm.github.io/k8s-device-plugin/, namespace:
  default, ServerSideApply: "true"}`; **no top-level `amd-gpu:` values block exists**
  (chart renders at defaults). The base appset (`charts/base/templates/appset-charts.yaml`)
  turns external-chart entries into Argo Applications with `valuesObject` (merged
  custom/service/base values) and internal entries (`charts/` dir, no version/repository)
  with a git `path:` source — so a vendored chart is a first-class shape here [repo read].
- **Live** (readonly-ai-gpu-kubernetes, 2026-11-11): DaemonSet
  `amd-gpu-device-plugin-daemonset` container `amd-gpu-dp-cntr` image
  `docker.io/rocm/k8s-device-plugin:1.31.0.9`, **no command/args/env fields at all**
  (image CMD runs `-logtostderr=true -stderrthreshold=INFO -v=5` — strategy defaults to
  `single`); hostPath `/sys` + `/var/lib/kubelet/device-plugins` + health dir;
  drop-ALL non-privileged. Node `ai-gpu`: capacity=allocatable `amd.com/gpu: 2`,
  **zero amd.com/* node labels** (no labeller, no NFD feature labels — stock k3s only)
  [R6-S12]. llama-swap live pod: main container requests cpu 1/mem 4Gi + **limits
  `amd.com/gpu: 1`** (requests auto-mirror for extended resources) [R6-S12].
- **The chart gap (decisive)**: the published helm index at
  rocm.github.io/k8s-device-plugin lists **0.22.0 (appVersion 1.31.0.9, created
  2026-09-02, digest `791ada88f09b…`) as the newest entry** — no chart release
  post-dates plugin .12. The chart **at the v1.31.0.12 tag itself, and on master,
  is still 0.22.0**: `Chart.yaml version: 0.22.0 / appVersion: "1.31.0.9"` and the
  DaemonSet template contains **no `args:`/`command:`/config-map hook** — the container
  block is image/securityContext/volumeMounts/resources only. values.yaml (0.22.0 and
  master) exposes `dp.image.{repository,tag}`, `dp.resources`, `dp.updateStrategy`,
  securityContext/tolerations/nodeSelector, labeller toggles — **nothing naming-related**
  [R6-S6][R6-S7]. The upstream fix is **open PR #122 "Support args, command for helm
  chart"** (created 2025-04-22, still unmerged) [R6-S7].
  → **No values-only path to the flag exists today.** The image bump IS values-reachable
  (`dp.image.tag: 1.31.0.12` — tag exists on Docker Hub, amd64 digest
  `sha256:6437c74f6566…` [R6-S13]), the flag is not.
- **Exact GitOps shape for option 1** (vendor route, repo-only):
  1. New internal chart `charts/amd-gpu/` — copy of upstream 0.22.0 (templates
     deviceplugin-daemonset/rbac/serviceaccount; `labeller.enabled: false`,
     `nfd.enabled: false` as today) **plus** in `deviceplugin-daemonset.yaml`, inside
     the container block:
     ```yaml
     args:
       - -logtostderr=true
       - -stderrthreshold=INFO
       - -v=5
       {{- with .Values.dp.extraArgs }}
       {{- toYaml . | nindent 6 }}
       {{- end }}
     ```
     (image CMD must be restated the moment `args:` is declared — Dockerfile CMD
     `["./k8s-device-plugin","-logtostderr=true","-stderrthreshold=INFO","-v=5"]`
     [R6-S5]; omitting `-v=5` silently drops the enumeration logs the runbook
     needs). Values default `dp.extraArgs: ["-resource_naming_strategy=product"]`.
  2. `services/gpu-ai/prod/values.yaml`: replace the `charts.amd-gpu` entry's
     version/repository with an internal entry (name collision with the old external
     release: the Application name derives from serviceName+appName — the
     `gpu-ai-amd-gpu` Application just switches source from repo-chart to git-path;
     same object, no orphan prune. The old *external* chart's resources keep identical
     names (`amd-gpu-device-plugin-daemonset`, selector `name=amd-gpu-dp-ds`) because
     the vendored templates hardcode `.Chart.Name` = amd-gpu — pin the vendored chart's
     `name` field to `amd-gpu`), and add the top-level values block
     `amd-gpu: { dp: { image: { tag: "1.31.0.12" } } }` (or bake the tag in the vendored
     Chart.yaml appVersion). Follows AGENTS.md chart rules (vendored third-party chart
     = a repo decision to log in DECISIONS; `version: 1.0.0` if created as a brand-new
     chart entry).
  3. Same wave: `charts/llama-swap/values.yaml:1045` flips `amd.com/gpu: 1` →
     `amd.com/gpu-8060s: 1`, comment block 1331-1338 ("fallback once a naming-capable
     plugin exists") retires as REALIZED.
  - Alternatives for step 1: **Argo CD `postRender`** (kustomize) attached per
    Application to inject the args — needs a small base-appset template addition and
    keeps the upstream chart pinned; or wait for PR #122 / an upstream chart ≥0.23
    (unbounded, PR stale 19+ months). Vendoring is the self-owned lane.

### R6-Q3 — ALTERNATIVES, EVIDENCED AND RANKED

(a) **Two plugin DaemonSets each pinned to one device — DEAD.** Source-verified: the .12
    plugin has no device-selection surface (sysfs glob enumerates all bound devices;
    no allowlist env/flag/config; `AMD_GPU_DEVICE_COUNT` is docs-only at this tag; the
    dpm Lister derives the same name list from the same full enumeration in every
    instance). Two DaemonSets would collide on identical resource names/sockets. The only
    in-repo "filter" the plugin offers is which *names* it advertises, and `product`
    already gives both cards their own names from ONE instance [R6-S1][R6-S2].

(b) **generic-device-plugin sidecar (squat) — WORKING LAB PRECEDENT, weak pin.**
    The repo already vendors `charts/generic-device-plugin` (app-template chart for
    `ghcr.io/squat/generic-device-plugin`, privileged, config `devices.yaml`,
    `DOMAIN=squat.ai`) and runs it in two clusters today: services/home/prod (zigbee
    `/dev/ttyUSB1`, zwave, snd `/dev/snd`, ec25 by USB vendor/product) and
    services/infra/prod (hdd paths with per-group `mountPath`) [repo reads]. Applied
    here: a gpu-ai entry exposing one device `r9700` whose group paths
    `/dev/kfd` + `/dev/dri/renderD<minor-of-R9700>` → pods request
    `squat.ai/r9700: 1`, non-privileged, Guaranteed — radiance never touches the
    amd pool; llama-swap untouched. Cons: the pin is by **render minor** (the lab's own
    enumeration-order scars [S15] and DRA issue #83 (minors shift across reboots/
    hotplug/mixed DRM) apply verbatim); the amd plugin still counts the R9700 inside
    `amd.com/gpu: 2` (same cross-system double-book class as strata today); no
    scheduler-level exclusivity. Effort: LOWEST (chart exists, values idiom proven).

(c) **DRA via ROCm/k8s-gpu-dra-driver — PRODUCTION-PROVEN ON THIS CARD CLASS.**
    - Driver: repo ROCm/k8s-gpu-dra-driver ("K8s DRA driver for AMD GPUs", active,
      pushed today), releases v1.0.0 2026-05-20, **v1.0.1 2026-07-22**; published helm
      repo `https://rocm.github.io/k8s-gpu-dra-driver` chart **v1.0.1** (kubeVersion
      `>=1.32.0-0`, digest `0fc24145a327…`); image `docker.io/rocm/k8s-gpu-dra-driver:
      v1.0.1` present [R6-S8][R6-S13]. DeviceClass `gpu.amd.com` created by default;
      each full GPU is a DRA Device with attributes `type=amdgpu`, `deviceID`
      (sysfs PCI id, e.g. `0x7551`), `productName`, `numaNode`,
      `resource.kubernetes.io/pciBusID` (unique per card), `pcieRoot` + capacities
      `memory`/`computeUnits`/`simdUnits`; claims CEL-select per device
      [R6-S8-attrs].
    - **k8s-side fits the lab**: DRA core GA in Kubernetes v1.34 (k8s blog 2025-09-01;
      "stable since 1.35, gate locked"), lab k3s = **v1.36.5** → `resource.k8s.io/v1`
      on by default. Kubelet plugins live under `/var/lib/kubelet/plugins{,_registry}`
      (chart defaults) — same layout k3s uses [R6-S14][R6-S8].
    - **Witness 1 (dsluo/homelab — the S11 production witness, mechanism now verified)**:
      runs the driver (`amd-gpu-dra-driver` Flux HelmRelease, image
      `ghcr.io/dsluo/k8s-gpu-dra-driver:v1.0.1-pr117@sha256:69ecc364…` — their fork for
      an NVIDIA-mixed era, "drop on the next upstream release"; values pin
      `cdi.dynamicPath: /var/cdi/dynamic`) and pins radiance to the R9700 with a
      **ResourceClaimTemplate `r9700`**: `deviceClassName: gpu.amd.com` + CEL
      `device.attributes["gpu.amd.com"].deviceID == "0x7551"` (+ `r9700-x2` with
      `allocationMode: ExactCount, count: 2` for TP2). Its header comment is the answer
      to the owner's exact topology question: "Pins the R9700 (1002:7551); the Raphael
      iGPU (1002:164e), **which the driver also advertises**, is never allocated" —
      i.e. heterogeneous APU+dGPU nodes advertise BOTH, selection is attribute-side,
      and the pod consumes via `resources.claims`/`spec.resourceClaims`. Their radiance
      Model CR (`qwen3-8-flash-next`) runs the same image pin the plan uses
      (`docker.io/stilldeadcode/radiance:1.17.0@sha256:6fb0e99b…`) [R6-S9].
    - **Witness 2 (driver issue #135 field report, VERIFIED-by-proxy)**: **Kubernetes
      v1.36.6 (K3s)**, 2× Radeon AI PRO R9700 (gfx1201, 32 GB), driver v1.0.1:
      discovery publishes both cards (`deviceID=0x7551, …, memory=32624Mi,
      computeUnits=64`), **card selection via CEL on `pciBusID` works**, a **restricted
      non-root, drop-ALL pod received exactly `/dev/kfd` + one `renderD*` through CDI
      and PyTorch saw the single gfx1201 device** — the Q7 pod shape, end to end, on
      the same runtime. Caveats from the same report: `productName` is EMPTY on Radeon
      sysfs (select by deviceID/pciBusID, never productName); `driverVersion` omitted
      on in-kernel amdgpu (v1.0.1 tolerates it — lab kernel 7.3.0 in-kernel amdgpu,
      same case) [R6-S10].
    - Open-bug ledger: #75 (CDI specs not restored from checkpoint after **node
      reboot**; fix PRs #78/#86 open) — mitigated by persistent `cdi.dynamicPath`
      (dsluo's exact values line); #83 (device names `gpu-<card>-<render>` are
      minor-derived, unstable across reboots — claims referencing stale names can
      prepare a different physical card; mitigated in practice because fresh claims
      re-resolve at scheduling, and by pciBusID/deviceID selectors, but a long-lived
      standalone shared claim + reboot is the exposure). No preemption for DRA pods
      (k8s docs limitation) — irrelevant at replicas=1/Recreate.
    - Refinement worth knowing: `deviceClass.extendedResourceName` (chart default
      `amd.com/gpu`) maps **classic** `vendor/name` requests onto DRA classes with no
      per-pod claim (KEP "DRA extended resources": alpha 1.35 → **beta 1.36** → GA
      1.37 [R6-S15]) — so a lab variant could define a selector-constrained class
      answering `amd.com/gpu-ai-pro-r9700` without touching pod specs. On k3s v1.36
      that's beta-on-by-default (verify on-target). Not the primary shape (two
      mechanisms mapping one name would fight the product-naming option; pick one).
    - **Set `deviceClass.extendedResourceName: ""` if this runs ALONGSIDE the still-
      single-strategy amd.com device plugin**, else the DRA class and the plugin both
      claim `amd.com/gpu` (values comment: "Override to another name, or set "" to omit").

(d) **Others checked**: AMD GPU Operator v1.5.1 ships the DRA driver as
    `DeviceConfig.spec.draDriver.enable` with the device plugin disabled (the #135
    reporter's actual install path) — heavyweight for one node [R6-S10].
    Node labeller/NFD labels (`amd.com/gpu.product-name`) label nodes but are not
    schedulable pools — cosmetic here, and the lab doesn't run the labeller at all
    (live labels empty [R6-S12]). `mixed` strategy on this node yields exactly
    `amd.com/gpu: 2` (both unpartitionable → default bucket) — a no-op, confirming the
    earlier reading's scope.

**Ranking for the owner's ask** (determinism · GitOps-only · llama-swap blast radius ·
effort):
| option | determinism | repo-only | llama-swap churn | effort |
|---|---|---|---|---|
| 1. plugin `product` + vendored chart | HIGH (kubelet per-name pools, choice at schedule+allocate) | YES (charts/ + services values) | **one request-line flip + its rollout** (see R6-Q4-2) | MED (small chart vendor) |
| 2. DRA driver alongside plugin | HIGHEST (attribute CEL pin, witness on identical card+runtime) | YES (external chart entry + claim template in charts/radiance) | **ZERO** (llama-swap never touched) | MED-HIGH (second GPU subsystem; reboot-CDI bug + minor-name caveats to gate) |
| 3. generic-device-plugin sidecar | MED (minor-path pin, no pool exclusion) | YES (chart already vendored) | ZERO | LOW |
- **Recommendation: option 1** — it is the literal owner ask (two resource NAMES,
  per-device), from the one mechanism upstream built precisely for "nodes holding more
  than one GPU product" [R6-S3], keeping the single amd pool semantics; the chart gap
  is a 10-line vendored template, and the llama-swap flip is what finally makes its APU
  assignment *explicit* (today it is an accident of nodeId order, the very fragility
  the card's Q9 names). Offer **option 2 as the strong alternative** (and the natural
  TP2 path — dsluo's `r9700-x2` claim + `--tp 2` is exactly C03's expansion, already
  in production) if the owner prefers zero llama-swap churn over literal naming.
  Never ship option 3's minor-path pin while option 1/2 exist.

### R6-Q4 — CONSEQUENCES FOR THE PLAN (table)

Assumes option 1 unless noted. (DRA variant in the last row.)

| # | Surface | Change |
|---|---|---|
| 1 | charts/radiance resources (C02) | `requests/limits: amd.com/gpu-ai-pro-r9700: 1` **instead of** `amd.com/gpu: 1` (cpu 8 / mem 52Gi pairs unchanged; extended resources still require equal request+limit for Guaranteed). The D14 "mis-allocation is possible" premise is **superseded** — with per-name pools the startup-report PCI gate demotes from MANDATORY-retry-gate to a cheap assert (keep it; it also catches the fallback-name trap). C02's plugin-facts comment block (APU-first, no occupancy) must be rewritten: strategy `product`, per-name pools, choice deterministic; "no occupancy check" stays TRUE (open PRs #243/#247) and strata's hostPath R9700 still sits inside the named pool's *physical* card — the radiance-vs-strata VRAM law (Q11) is unaffected by naming. |
| 2 | llama-swap (charts/llama-swap/values.yaml:1045 + comment 1331-1338) | `limits.amd.com/gpu: 1` → `amd.com/gpu-8060s: 1` (requests auto-mirror). **After the strategy flip `amd.com/gpu` no longer exists on the node — a llama-swap pod recreated before this flip lands is unschedulable (Pending)**. The running pod keeps running through the plugin rollout (device allocations belong to the running container; kubelet does not evict on plugin-name changes [R6-S16]) but its NEXT restart needs the new name. Ship the flip in the same Argo wave as the plugin (Deployment keeps serving the old pod until the new one with `gpu-8060s` becomes Ready → scheduled to the APU bucket = exactly one device = the APU; owner ask satisfied explicitly). The comment's "fallback once a naming-capable plugin exists: amd.com/gpu + IPC_LOCK/SYS_RESOURCE + non-privileged" becomes realized-fact prose. |
| 3 | strata / vllm hostPath pods | **No interaction, confirmed**: neither requests `amd.com/gpu` today (live: strata pod has no GPU extended-resource request [R6-S12]; charts/vllm sets ROCR/HIP env inside its privileged hostPath pod, never the plugin claim) — node status losing `amd.com/gpu` changes nothing for them. Q5 (strata stays) + Q10 (manual scale-down) stand untouched. The one nuance: with `product` the pool that llama-swap's *flipped* name reads is now the APU-only bucket — a future stray `amd.com/gpu: 1` request anywhere becomes Pending-forever instead of silently landing on a card (loud by design). |
| 4 | migration risk | The DaemonSet rollout (image 1.31.0.9→1.31.0.12 + args + source now the vendored chart) restarts ONLY the plugin pod — running GPU pods are untouched (allocation is container-creation-time; the plugin already restarted 19× without moving pods [S14]). The real state change is node status: `amd.com/gpu: 2` → `amd.com/gpu-ai-pro-r9700: 1, amd.com/gpu-8060s: 1` **once the new plugin registers** (deregistration gap of seconds during pod swap: system-node-critical, no scheduling storm expected on a single-node idle cluster). Rollback = re-apply old chart pin (no args) — the flip restores `amd.com/gpu: 2`; a llama-swap pod already flipped to `gpu-8060s` must roll back in lockstep (values history is GitOps — one `git revert` of the same wave). Argo re-points `gpu-ai-amd-gpu` from the external repo-chart to the git-path chart with the SAME rendered object names — no orphaned resource; watch `ignoreDifferences`/SSA field ownership on the args field once (ServerSideApply: "true" today helps). |
| 5 | C06 runbook step-0 gates (add) | (a) host receipt: `cat /sys/module/amdgpu/drivers/pci:amdgpu/*/device /sys/.../revision` per BDF c4/c5 → match against the vendored table rows (`7551 C0` expected for the R9700; `1586 C1/C3/C6/D1` for the 8060S) BEFORE relying on either name — mismatch means that card lands under bare `amd.com/gpu`; (b) plugin log receipt: "Loaded N GPU products from /usr/share/libdrm/amdgpu.ids" + "Reporting 1 devices as amd.com/gpu-…" lines (keep `-v=5`); (c) node-status assert: both expected names at 1 **and** decide explicitly whether `amd.com/gpu` should be absent (absent = both cards matched; present-1 = a fallback fired, fix the flip list or pin the claim by the name that materialized); (d) llama-swap post-rollout check: pod Running + startup log still names the unified-vulkan APU path; (e) radiance startup-report PCI/gfx1201 assert retained as belt-and-braces (now redundancy, was necessity). |
| DRA variant | if option 2 wins instead | charts/radiance ships NO extended-resource GPU line at all: `spec.resourceClaims: [{name: gpu, resourceClaimTemplateName: radiance-r9700}]` + container `resources.claims: [{name: gpu}]` (claim template = CEL `deviceID == "0x7551"` — dsluo's exact shape [R6-S9]); llama-swap untouched (plugin stays 1.31.0.9/single); services adds chart entry `k8s-gpu-dra-driver` (repo rocm.github.io/k8s-gpu-dra-driver, version v1.0.1) with `deviceClass.extendedResourceName: ""`, `cdi.dynamicPath: /var/cdi/dynamic`, nodeAffinity-less (single node), image pinned by digest; runbook gates become: ResourceSlice lists both devices w/ attributes; container CDI injection check (non-root restricted pod precedent [R6-S10]); reboot-then-verify-claim prepared path (#75). Q4(5)-gates (b)(d)(e) carry over. |

### R6-Q5 — VERIFICATION FACTS (receipts)

- Plugin source: ROCm/k8s-device-plugin tag `v1.31.0.12` — `internal/pkg/naming/naming.go`
  (Strategy consts incl. `StrategyProduct`; ResourceName product branch w/ style
  suffix rule; 63-char truncate), `internal/pkg/naming/products.go` (IDsPath
  `/usr/share/libdrm/amdgpu.ids`; filler set incl. radeon/graphics/series, `pro`/`rx`
  deliberately kept; collision→qualify), `cmd/k8s-device-plugin/main.go` (flag
  `-resource_naming_strategy` default `single`; **no** config-file/env strategy path),
  `internal/pkg/plugin/plugin.go` (`bucketDevices` per-name; dpm one-plugin-per-name;
  Allocate = `/dev/kfd`+card/render only, no env), `Dockerfile` (bakes
  `cmd/k8s-node-labeller/amdgpu.ids` → IDsPath; CMD w/o strategy flag),
  `k8s-ds-amdgpu-dp.yaml` (upstream raw DS: also no args). Tag v1.31.0.11:
  `internal/pkg/naming/naming.go` → HTTP 404 [R6-S1,S2,S5].
- PR #246 "feat: add `product` resource naming strategy", merged
  2026-10-19T19:21:59Z (closes #128; body examples `amd.com/gpu-mi300x-cpx-nps4`,
  `amd.com/gpu-mi210`) [R6-S3]. Release v1.31.0.12 published 2026-11-06T17:55:49Z;
  image `docker.io/rocm/k8s-device-plugin:1.31.0.12` exists, amd64 digest
  `sha256:6437c74f6566…` [R6-S2,S13].
- Chart: `rocm.github.io/k8s-device-plugin/index.yaml` newest amd-gpu entry =
  0.22.0, appVersion 1.31.0.9, created 2026-09-02T20:13Z, digest
  `791ada88f09b5159ad89f2c006b61079d075d020f924cafd5fe3e31712232695` (then 0.21.0,
  0.20.0, …) [R6-S6]. Chart.yaml @tag v1.31.0.12, @tag amd-gpu-helm-0.22.0 AND @master:
  `version: 0.22.0 / appVersion: "1.31.0.9"`; DS template identical across all three —
  no args hook; open PR #122 (2025-04-22) still unmerged [R6-S6,S7].
- DRA driver: ROCm/k8s-gpu-dra-driver — releases v1.0.0 2026-05-20, v1.0.1
  2026-07-22T18:46Z; helm index: chart v1.0.1 (appVersion v1.0.1),
  `urls[0]=…/charts/k8s-gpu-dra-driver-v1.0.1.tgz`, digest
  `0fc24145a3273c3448d53c0e909f7fa12825b67f569fd67074624a21fbcce589`, kubeVersion
  `>=1.32.0-0`; image `docker.io/rocm/k8s-gpu-dra-driver:v1.0.1` exists; values:
  `deviceClass.create: true`, `deviceClass.extendedResourceName: amd.com/gpu` (override
  ""), `cdi.dynamicPath` default `/var/run/cdi` (dsluo pins `/var/cdi/dynamic`),
  kubelet plugin dirs `/var/lib/kubelet/plugins{,_registry}`, privileged plugin+init
  containers, busybox:1.36 init [R6-S8]. Attributes doc + issue #135 + dsluo
  `resourceclaimtemplate.yaml`/`qwen3-8-flash-next.yaml`/`helmrelease.yaml` as cited
  [R6-S8-attrs,S9,S10].
- Node/hardware product strings: R9700 = PCI `1002:7551` — independently attested by the
  engine's own rig doc ReBAR check `lspci -d 1002:7551 'Region 0'` [S3] and the vendored
  table row `7551, C0, AMD Radeon AI PRO R9700`; 8060S = `1002:1586` [S17], table rows
  `1586,C1/C3/C6/D1 = AMD Radeon 8060S Graphics` (audio function 1002:1640 [S17]). The
  launch brief's bracket-style string "Advanced Micro Devices, Inc. [AMD/ATI] Strix…"
  is the lspci *class* spelling, not the amdgpu.ids marketing column — naming uses the
  table, so it cannot leak into resource names; and the fallback that WOULD name a card
  `amd.com/gpu` is reserved for unknown (device,revision) pairs [R6-S5].
- Live (readonly-ai-gpu-kubernetes, 2026-11-11): node `ai-gpu` capacity/allocatable
  `amd.com/gpu: 2`, no `amd.com/*` labels; DS container spec as in R6-Q2 (no args/env,
  image 1.31.0.9); llama-swap pod main container limits `amd.com/gpu: 1` (+ requests
  cpu1/4Gi), tools sidecar GPU-free [R6-S12].
- Repo request lines: `charts/llama-swap/values.yaml:1045` (`amd.com/gpu: 1`, the ONLY
  in-repo claim today); strata block requests = cpu/mem only (110Gi/8 CPU class,
  privileged hostPath, values ~1300-1338 incl. the naming-capable-plugin comment);
  `charts/vllm/values.yaml:307,310,372` = ROCR/HIP env inside its hostPath pod (no
  plugin claim); services amd-gpu entry 40-44; base appset charts generator + internal
  path rendering (appset-charts.yaml:16-39, 64-70, 114-123).

### R6 — Contradictions & corrections to earlier rounds

- RESEARCH line 670 ("a chart bump gives per-product resources (amd.com/Radeon-AI-
  PRO-R9700)"): both halves need correction — the name form is `amd.com/gpu-ai-pro-r9700`
  and **no chart bump exists** (0.22.0 cannot render args; master still 0.22.0). The
  mechanism is real; the Helm delivery isn't shipped upstream [R6-S5,S6,S7].
- Earlier "product naming PR #246 merged → deferred as near-prerequisite" (D14):
  this round upgrades the record from "clean fix, later" to "clean fix, blocked by a
  stale upstream chart PR, deliverable now via a 10-line vendored chart" — the
  own-concern Deferred framing (DECISIONS) understates that a repo-only path exists.
- Plan D14/Q9 shipped posture (`amd.com/gpu: 1` + mandatory PCI-retry gate) is
  **superseded by owner ruling** — the Q9 round exists precisely to replace the
  best-guess with the named scheme; the gate survives as redundancy.
- The docs' `AMD_GPU_DEVICE_COUNT`/`CONFIG_FILE_PATH` (configuration.md @.12) are not
  implemented in the .12 binary (flag surface only) — earlier round's "not re-verified"
  is now resolved; neither would have helped anyway (count ≠ choice) [R6-S2].

### R6 — Adjacent (cheap, worth recording)

- Occupancy: PRs #243 "Add opt-in KFD GPU occupancy check" + #247 "Kfd occupancy
  prestart" are OPEN (2026-09/10) — upstream concedes the no-occupancy class; a future
  bump could make even the within-bucket choice occupancy-aware. Watch, don't wait.
- DRA extended-resource mapping (beta 1.36, GA 1.37) means the lab could later serve
  *classic-named* per-card requests without per-pod claims — a clean migration lane if
  the owner ever moves llama-swap (and the home clusters' squat.ai devices) onto the
  DRA driver wholesale [R6-S14,S15].
- `--prefill-interleave auto:1` landed post-1.17.0 (unchanged from earlier round) — no
  interaction with naming.

### R6 — Open questions (residual — ride the RESULT too)

1. **On-target revision match**: the lab APU's sysfs `revision` must be one of
   C1/C3/C6/D1 (→ `gpu-8060s`) and the R9700's C0 (→ `gpu-ai-pro-r9700`); unknown
   revision = that card silently lands under bare `amd.com/gpu` (fallback). C06 step-0
   receipt closes it (also fixes which render minor /dev paths would have needed for
   option 3).
2. **Owner lane choice**: vendored amd-gpu chart (recommended) vs DRA-alongside (zero
   llama-swap churn, strongest determinism, second subsystem + open reboot-CDI bug) vs
   squat sidecar. DRA-vs-plugin is a philosophy call the owner has not reserved; both
   are repo-only.
3. If option 1: the exact vendored-chart governance line (DECISIONS: third-party chart
   vendored at digest/tag `amd-gpu-helm-0.22.0` + the args delta; future re-sync
   procedure) — plan-level, not research-level.
4. Strix APU enumeration under the DRA driver (gfx1151 via amd_smi) has no field
   report located (Raphael iGPU advertised per dsluo; Radeon dGPU proven per #135) —
   only relevant if option 2 wins; runbook ResourceSlice check settles it.

### R6 — Sources (accessed 2026-11-11)

| # | URL | What it is |
|---|---|---|
| R6-S1 | raw.githubusercontent.com/ROCm/k8s-device-plugin/v1.31.0.12/internal/pkg/naming/naming.go (+ …/plugin/plugin.go) | strategy constants, ResourceName/bucketDevices/dpm per-name plugin, Allocate surface |
| R6-S2 | same tag: cmd/k8s-device-plugin/main.go, Dockerfile, docs/user-guide/configuration.md, k8s-ds-amdgpu-dp.yaml | flag surface (`-resource_naming_strategy` default single), IDs table baked at /usr/share/libdrm/amdgpu.ids, docs-vs-code drift (device_count/config-file not implemented) |
| R6-S3 | api.github.com/repos/ROCm/k8s-device-plugin/pulls/246 | PR "feat: add `product` resource naming strategy", merged 2026-10-19T19:21:59Z, body rationale + name examples |
| R6-S4 | same tag: docs/user-guide/configuration.md §Resource Naming Strategy + README.md | single/mixed/product semantics; MI300X/MI210 worked examples; heterogeneous-node definition |
| R6-S5 | same tag: internal/pkg/naming/{products.go,products_test.go,naming_test.go} + cmd/k8s-node-labeller/amdgpu.ids | sanitizer/filler/collision rules + 752-row vendored table; JS port passing upstream fixtures; lab names gpu-ai-pro-r9700 / gpu-8060s |
| R6-S6 | rocm.github.io/k8s-device-plugin/index.yaml + tag trees amd-gpu-helm-0.22.0 & v1.31.0.12 helm/amd-gpu/** | newest chart 0.22.0 (appVersion 1.31.0.9, digest 791ada88…); template has NO args hook; values keys dp.image.tag/resources |
| R6-S7 | api.github.com ROCm/k8s-device-plugin pulls?state=open | open PR #122 "Support args, command for helm chart" (2025-04-22) + open occupancy PRs #243/#247 |
| R6-S8 | ROCm/k8s-gpu-dra-driver repo: README, releases API, rocm.github.io/k8s-gpu-dra-driver/index.yaml, helm-charts-k8s/values.yaml, docs/driver-attributes.md, example/example.yaml | DRA driver v1.0.1; chart v1.0.1 digest 0fc24145…; DeviceClass gpu.amd.com; attributes (deviceID/pciBusID/type/capacity); claim-template + resources.claims shape; extendedResourceName default amd.com/gpu (override/"") |
| R6-S9 | raw.githubusercontent.com/dsluo/homelab/main/kubernetes/apps/{ai/llmkube/models/resourceclaimtemplate.yaml, ai/llmkube/models/qwen3-8-flash-next.yaml, kube-system/amd-gpu-dra-driver/app/helmrelease.yaml} | production R9700 pin via CEL deviceID==0x7551 (+x2 TP2), radiance 1.17.0@6fb0e99b pod spec, driver fork image + persistent cdi.dynamicPath |
| R6-S10 | api.github.com/repos/ROCm/k8s-gpu-dra-driver/issues/135 | field report: k3s v1.36.6 + 2×R9700 gfx1201, v1.0.1 works incl. restricted non-root pod /dev/kfd+renderD via CDI; productName empty on Radeon; gpu-operator v1.5.1 deploy path |
| R6-S11 | api.github.com …/issues/{75,78,83,86} | reboot-CDI-restore bug + fix PRs open; minor-derived device names unstable |
| R6-S12 | readonly-ai-gpu-kubernetes (live): Node ai-gpu, DaemonSet amd-gpu-device-plugin-daemonset, Pod gpu-ai-llama-swap-* | capacity amd.com/gpu:2, no amd.com labels, DS no args/env image 1.31.0.9, llama-swap limits.amd.com/gpu:1 |
| R6-S13 | hub.docker.com/v2/repositories/rocm/{k8s-device-plugin/tags/1.31.0.12, k8s-gpu-dra-driver/tags/v1.0.1} | both images exist (amd64 digest 6437c74f… for the plugin) |
| R6-S14 | kubernetes.io/blog/2025-09-01/kubernetes-v1-34-dra-updates + …/docs/concepts/resource-management/dynamic-resource-allocation | DRA core GA v1.34; stable/locked v1.35; no preemption for DRA pods |
| R6-S15 | kubernetes.io/blog/2026-09-03/kubernetes-v1-37-dra-updates | DRA extended-resource mapping: alpha 1.35 / beta 1.36 / GA 1.37 |
| R6-S16 | kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins | device-plugin framework semantics (Allocate at container creation; unhealthy-device pods keep assignments, counts change at scheduling; extended resources integer-only, no overcommit; ResourceHealthStatus beta 1.36) |

RESULT
status: DONE
chunk: plan
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md]
commands_run: [repo reads (services/gpu-ai/prod/values.yaml, charts/base/templates/appset-charts.yaml, charts/llama-swap values+grep, charts/generic-device-plugin, home/infra generic-device-plugin values, STATE.json, chunks/C02.md, charts/radiance existence) => pass; github api: ROCm/k8s-device-plugin releases+PRs(#246 merged, #122/#243/#247 open)+git-trees(v1.31.0.12, amd-gpu-helm-0.22.0, master)+raw source (main.go, naming.go, products.go, both tests, plugin.go, amdgpu.go, Dockerfile, helm values/Chart/dstpl@tag+master, configuration.md, k8s-ds yaml, amdgpu.ids 752 rows) => pass; JS port of naming/products against the vendored table + self-test vs upstream fixtures (5/5 pass) => pass; ROCm/k8s-gpu-dra-driver repo/releases/index/values/deviceclass/attrs-doc/example/issues 135/83/75 => pass; rocm.github.io indexes (amd-gpu 0.22.0 newest; dra-driver v1.0.1) => pass; dsluo/homelab raw manifests (claim template, flashnext Model+IS, dra HelmRelease) => pass; hub.docker.com tag checks (plugin 1.31.0.12, dra v1.0.1) => pass; readonly-ai-gpu-kubernetes: resources_get Node ai-gpu + DaemonSet amd-gpu-device-plugin-daemonset, pods_get gpu-ai-llama-swap-* (read-only throughout) => pass; websearch ×2 (DRA GA citations, containerd CDI) + webfetch k8s device-plugins docs => pass]
deviations: storm fan-out inline again (no subagent harness); the "two DaemonSets with a device filter" alternative was researched-to-exhaustion from source rather than docs (no filter exists in the .12 binary); discovered and sourced a third real mechanism (ROCm DRA driver) beyond the brief's option list — it is the only production-evidenced path that gives per-device determinism WITHOUT touching llama-swap, so it is ranked #2 rather than parked in Adjacent.
friction: raw.githubusercontent 404s on guessed template filenames (configmap.yaml / amd-gpu-device-plugin-daemonset.yaml) — resolved by recursive git-trees listing per ref (the templates are helm/amd-gpu/templates/{deviceplugin-daemonset,labeller,rbac,serviceaccount}.yaml + _helpers/NOTES only); helm index entries sort by version-descending but a naive regex matched the OLDEST entry first — re-parsed with an anchored regex; GitHub code-search API needs auth — replaced with targeted tree+raw reads; earlier-round note that chart "values.yaml 404'd" is explained: the chart lives at helm/amd-gpu/ in the tag tree, not repo-root.
open_questions: [owner lane: option 1 (vendored amd-gpu chart + product naming, literal ask, one llama-swap request-line flip in-wave) vs option 2 (k8s-gpu-dra-driver v1.0.1 ResourceClaimTemplate pin, zero llama-swap churn, second GPU subsystem + open reboot-CDI bug mitigated by persistent cdi.dynamicPath) — R6 recommends 1, offers 2 as the strongest alternative and the natural TP2 path; on-target sysfs device+revision receipts for both cards decide the exact advertised names (fallback trap: unknown revision → bare amd.com/gpu); if option 2: gfx1151 APU enumeration by the DRA driver is unevidenced (Raphael iGPU + R9700 are) — ResourceSlice check gates it; if option 1: vendored-chart governance line for DECISIONS]
next_suggested: coord folds R6 into the plan as the Q9 ruling round: replace D14/plan "Q9 best guess" with the two-option decision table (recommend option 1: vendored charts/amd-gpu at 0.22.0+args, dp.image.tag 1.31.0.12, radiance requests amd.com/gpu-ai-pro-r9700, llama-swap flips to amd.com/gpu-8060s same-wave, C06 step-0 gains the revision/name gates), and put option-1-vs-2 (plus the two runbook receipts) to the owner in the next batched question round before C02 starts.

---

## §R7 — Customizing the product resource NAME (owner PR-review item 3; item 5 facts)

Owner wrote on the branch diff: "call this amd.com/r9700-1" (pointing at the rendered claim
line `amd.com/gpu-ai-pro-r9700: "1"`). Question: can the deployed ROCm k8s-device-plugin
v1.31.0.12 advertise a CUSTOM per-product name so the node exposes exactly
`amd.com/r9700-1`? Plus the item-5 facts the plan needs on the app-template conversion.
Every claim cites [R7-S#]; repo paths are branch state (read-only this round).

### R7 VERDICT (first, fold into the plan)

**RENAME POSSIBLE: NO.** The .12 binary (and master) has **zero** name-customization
surface: two flags only (`-pulse`, `-resource_naming_strategy`), no env, no config file,
no override map. Worse for the literal ask, even the unsupported table-mount hack cannot
reach `amd.com/r9700-1`: the resource name is assembled as
`"amd.com"` (hardcoded in `GetResourceNamespace()`, plugin.go) + `"/"` +
`"gpu-"` (hardcoded prefix: `dropWords()` returns `DefaultResource + "-" + …`, products.go)
+ sanitized-marketing. The best a custom `amdgpu.ids` row can produce is
**`amd.com/gpu-r9700-1`** — the owner's exact string is unreachable by any ROCm-plugin
mechanism, supported or not [R7-S1..S4]. **Plan answer per DECISIONS item 3's own
conditional ("if NOT → keep gpu-ai-pro-r9700 + answer the owner with evidence"): keep
`amd.com/gpu-ai-pro-r9700`; NO test re-pins, NO C07/C02 changes from item 3.
The two lanes that CAN literally surface `amd.com/r9700-1` are outside the owner's Option-1
ruling: (d) DRA `DeviceClass.spec.extendedResourceName` (k8s beta 1.36 — ON on the lab's
k3s v1.36.5, driver-agnostic cluster YAML) and (c) squat generic-device-plugin
`--domain amd.com` + device `name: r9700-1` (the §R6-rejected determinism lane).
Upstream feature ask (b): **no existing issue** — verified against the full open-issue
list 2026-11-12; filing one is cheap and is what item 3's "naming shape rides an upstream
ask" line expects [R7-S9].
**APP-TEMPLATE CONVERSION: YES, cleanly convertible** — daemonset type, args, hostPath
volumes, SA+ClusterRole via values, tolerations, priorityClassName, DirectoryOrCreate all
expressed in app-template 5.0.1 (schema + common templates cited from the vendored tgz);
the ONLY real gap is DaemonSet `updateStrategy` (not rendered; equals the k8s default the
chart sets today, so zero behavioral loss now — record it); object-name identity
(D19's byte-pin) is intentionally lost and replaced by a one-sync DS swap inside the
same C07-style wave [R7-S10..S14].

### R7-Q1 — Naming/config surface in the SHIPPED .12 binary (source-verified)

- `cmd/k8s-device-plugin/main.go @ v1.31.0.12` registers exactly TWO non-glog flags:
  `flag.IntVar(&pulse, "pulse", 0, …)` and `flag.StringVar(&resourceNamingStrategy,
  "resource_naming_strategy", "single", "Resource strategy to be used: single, mixed or
  product")`. glog's logging flags ride along (the Dockerfile CMD trio
  `-logtostderr=true -stderrthreshold=INFO -v=5`) — none naming-related. **No
  `-resource-naming-*` companions exist** [R7-S1].
- The product path in main.go: `naming.LoadProductIndex(naming.IDsPath)` — reads the
  **const** path, no alternative input. **No env var, no config file anywhere**: no
  `os.Getenv` in main.go, plugin.go, amdgpu.go (fetched and grepped, tag AND master)
  [R7-S1,S3,S4]. The docs' `CONFIG_FILE_PATH` YAML "configuration file" section is
  documentation-ahead-of-code at .12 (re-confirmed §R6; docs at the tag offer no custom
  names either — naming is "product name comes from amdgpu.ids") [R7-S5].
- **master == .12 here**: the naming package is the same 4 files at both refs
  (`naming.go`, `products.go` + tests — no overrides/registry file), master main.go has
  the identical 2-flag surface, master products.go still `const IDsPath =
  "/usr/share/libdrm/amdgpu.ids"` [R7-S2,S6]. So "wait for upstream config surface" has
  nothing in flight.
- The full config surface of the shipped binary is therefore: strategy ∈ {single, mixed,
  product}, pulse seconds, glog knobs. Nothing chooses NAMES beyond the table.

### R7-Q2 — products.go/naming.go derivation; the table-mount hack; what the sanitizer makes of "r9700-1"

- **Pure table derivation, no override consulted**: `ResourceName()`'s product branch is
  `products.Name(deviceID, revisionID)` — a `(device,revision)` → marketing-name lookup
  built by `LoadProductIndex(path)` from the parsed file only (firstMatch → foldCase →
  resolve/shorten/qualify). No map, file, env or flag is consulted before/after
  sanitizing [R7-S3].
- **Where it reads**: `IDsPath` is a `const` (not a var, not env): the plugin
  `os.Open`es `/usr/share/libdrm/amdgpu.ids` — the file the Dockerfile bakes
  (`COPY … cmd/k8s-node-labeller/amdgpu.ids /usr/share/libdrm/amdgpu.ids`) [R7-S3,S5].
  Nothing in the container forbids MOUNTING OVER that path (plain file read), so a
  custom-table volume is mechanically possible (hostPath `File`/`FileOrCreate` or a
  ConfigMap + subPath mount) — but it is **undocumented, unsupported, and contradicts
  upstream's stated design** ("supporting a new product is an `amdgpu.ids` update rather
  than a code change" = rebuild the image; issue #215 automates the table refresh in-tree,
  the opposite of a mount-your-own posture) [R7-S5,S9].
- **Sanitizer trace for marketing string `"r9700-1"`** (products.go `dropWords` +
  naming.go `SanitizeResourceName`): lowercase → unchanged; non-`[a-z0-9.-]` → none;
  `strings.Fields` → one token `r9700-1`; token ∉ filler set `{amd,ati,instinct,radeon,
  graphics,series}` (note `pro`/`rx` deliberately absent anyway) → kept; result =
  `truncate("gpu" + "-" + "r9700-1")` = **`gpu-r9700-1`** [R7-S3]. The `gpu-` prefix is
  `DefaultResource` concatenated **inside the code**, not the table — no row content can
  escape it (and `LoadProductIndex` explicitly drops rows deriving to bare `gpu`).
  Combined with the hardcoded `amd.com` namespace (plugin.go
  `GetResourceNamespace() { return "amd.com" }` — the dpm Lister contract; names come out
  as `amd.com/<sanitized>`), the string **`amd.com/r9700-1` is unreachable**; the closest
  any hack gets is `amd.com/gpu-r9700-1`.
- **Blast radius of a swapped table on THIS node**: rows are keyed by
  (device,revision), so editing the `7551, C0, AMD Radeon AI PRO R9700` row renames ONLY
  the R9700; the `1586` APU rows keep deriving `gpu-8060s` untouched — **the answer to the
  brief's "(does a rename touch gpu-8060s — likely YES?)" is NO per-row for the table
  route** (a global prefix/domain rename would hit both, but no such flag exists). Other
  lookups are safe iff the mounted file is a full copy with only the target rows edited
  (partial tables silently re-introduce the bare-`amd.com/gpu` fallback for any card whose
  row was dropped — the §R6-Q1 fallback trap, and this node has exactly the two cards so
  the exposure is bounded). Collisions: `resolve()` falls back to `qualify()` for products
  whose short names clash; `gpu-r9700-1` clashes with nothing in the 752-row vendored
  table. The -v=5 receipt "Loaded N GPU products from /usr/share/libdrm/amdgpu.ids" would
  report the mounted table's row count — runbook gate (b) pins the expected digest/row
  count of the override file if this hack is ever chosen.
- **Verdict on the hack**: mechanically live, strategically bad — buys `gpu-r9700-1` (NOT
  the owner's literal string) at the cost of an unsupported mount, a repo-owned copy of a
  file upstream refreshes by image rebuild (D19 refresh policy rewritten), and a ledger
  whose names no longer match the stock image (breaks §R6-Q4-5(c) name-provenance
  reasoning: "the name IS what the table says" stops holding). Not recommended.

### R7-Q3 — No mechanism ⇒ the alternatives, ranked

| # | lane | exact `amd.com/r9700-1`? | supported? | cost/caveat |
|---|---|---|---|---|
| 1 | (a) keep `amd.com/gpu-ai-pro-r9700` | no (sanctioned name) | YES — shipping as C07 | zero; the name is what the table+sanitizer say; "-1" carries no scheduling meaning (pool holds exactly 1 device) |
| 2 | (d) DRA `DeviceClass.spec.extendedResourceName` | **YES, literally** | YES (k8s feature: alpha 1.35, **beta 1.36** = on-by-default on the lab's k3s v1.36.5, GA 1.37) | lane-switch: installs the §R6 option-2 driver (rejected by the Option-1 ruling, D18); name is a **class-side pool, NOT node capacity** (nothing advertised under Node.status); §R6 bug ledger #75/#83 rides along |
| 3 | (c) squat generic-device-plugin | **YES, literally** (`--domain amd.com` + device `name: r9700-1` — upstream README flag surface confirmed) | YES (supported by squat; repo already vendors the chart) | stays REJECTED: the "never ship while 1/2 exist" line (DECISIONS D18 quoting §R6-Q3) referred to options **1=plugin product naming, 2=DRA driver** — squat's pin is the unstable renderD-minor path + it leaves the card double-booked inside the amd plugin's own pool (no scheduler-level exclusivity). The literal name does not cure the determinism objection |
| 4 | table-mount hack (§R7-Q2) | no (`gpu-r9700-1` at best) | NO (unsupported) | see §R7-Q2 verdict — can't even reach the exact string |
| 5 | (b) upstream feature ask | n/a | — | no existing issue [R7-S9]; do it regardless of the lane chosen |

- **(b) evidence for filing**: full open-issue list of ROCm/k8s-device-plugin fetched
  2026-11-12 (30 issues + 9 PRs open): NO issue asks for a custom resource name, name
  override, prefix or domain config. Nearest neighbors: #128 (per-product naming — CLOSED,
  delivered by PR #246 as the strategy we ship), #215 "Automate refresh of vendored
  amdgpu.ids" (OPEN 2026-08-24 — upstream treats the table as an image artifact, not an
  override surface), #45 "GPU isolation options" (OPEN 2024 — different axis), #149
  device-count on Minikube (OPEN), PR #122 args/command for the Helm chart (OPEN, stale —
  the chart gap D19 already works around) [R7-S9]. A new issue ("configurable resource
  name/prefix/domain, or a name-override side-map consulted before sanitize") has zero
  duplicates to reference; the #128→#246 arc is the precedent that naming-ergonomics asks
  DO land upstream.
- **(d) precise shape** (the only exact-string lane with real determinism): driver
  v1.0.1's own `deviceclass.yaml` creates `gpu.amd.com` with `spec.selectors` CEL and
  **no extendedResourceName at the tag** — the `deviceClass.extendedResourceName`
  values key is a MASTER addition (master values.yaml:28 `extendedResourceName:
  amd.com/gpu`, rendered conditionally) [R7-S7,S8] (see corrections: §R6-S8 quoted
  master). But the mapping itself is control-plane machinery (KEP-5004 family), NOT
  driver code: a hand-shipped DeviceClass `{spec: {selectors: [cel: driver=="gpu.amd.com"
  && deviceID=="0x7551"], extendedResourceName: amd.com/r9700-1}}` makes pod lines
  `amd.com/r9700-1: "1"` schedulable with **no claim stanza and no driver upgrade** —
  verified field contract from release-1.36 types.go: `ExtendedResourceName *string`,
  "same format as the name of a pod's extended resource", unique per cluster,
  `+featureGate=DRAExtendedResource`, beta; 1.36 blog "Extended resource support (beta)
  … request resources via traditional extended resources on a Pod"; 1.37 blog "set an
  extended resource name directly on a DeviceClass, and Pods requesting it get matched to
  a device through DRA with no ResourceClaim needed on the workload's part" [R7-S11,S12].
  Consequences if the owner takes it: it REPLACES the C07 product-naming delivery (the
  plugin can stay 1.31.0.9/single → llama-swap never flips → the D21 shield flip and every
  `gpu-8060s` string in tree become moot), and radiance's Determinism rides CEL-class
  selection (the §R6 option-2 evidence set: dsluo + #135 witnesses). This is a LANE
  decision for the owner (D18 already weighed and parked option 2) — research only flags
  that it is the sole supported way to get the literal string with allocation
  determinism. NOT a rename: tests/ledger/flip work of C07 re-scopes wholesale.

### R7-Q4 — (Mechanism exists? No —) so what the rename WOULD have touched, for the record

No rename ships this run (verdict NOT). If the owner nevertheless insists on the literal
string, the choice is a LANE switch (§R7-Q3 (d) or (c)), not a value edit — hence the
blast radius is the §R6-Q4 DRA-variant row / §R6-Q3(b) row, NOT "every string → new
name". For completeness, the current-tree inventory a hypothetical name change would
re-pin (grep of the two pool strings on this branch, 2026-11-12):

| surface | files (lines at grep) | note |
|---|---|---|
| radiance claim pair + comments | charts/radiance/values.yaml:77-78, 281, 285 | the owner-pointed line |
| radiance NOTES | charts/radiance/templates/NOTES.txt:25 | |
| radiance tests | tests/test_resource_name_identity.py:3,5,59,69 · tests/test_render.py:122,137 · radiance_testlib.py:95,97,266 | GPU_CLAIM/APU_CLAIM constants + ledger-parse |
| amd-gpu ledger | charts/amd-gpu/values.yaml:4-15 (7551/C0→gpu-ai-pro-r9700, 1586→gpu-8060s) | per-ROW scoped |
| amd-gpu tests | tests/test_provenance.py:162,180 · amd_gpu_testlib.py:9-10,21,65-66 | ledger triples |
| llama-swap comments + flip test | charts/llama-swap/values.yaml:1054,1346-1347 · tests/test_cf143_naming_flip.py:9,14,41-42,66,131,144,191 | |
| gpu-ai overlay | services/gpu-ai/prod/values.yaml:49-50, 171, 173 | the APU claim lines (D21 shield) — **untouched by a per-row R9700 rename; retired entirely only in the (d)/(c) lane switches** |
| validation | tests/services/amd-gpu-naming.sh:10,48-49,173-176,191,196,213-216,220 · tests/notes/radiance-runbook.sh:251-252 · tests/notes/radiance-tp2.sh:207 | n3/n4 sweeps + runbook/TP2 name assertions |
| pipeline artifacts | chunks C06/C07 prose, DECISIONS D18/D19/D21 lines | coord-owned |

**D18 same-wave law applies to any rename**: the advertised name and every consumer claim
line flip atomically (one wave / C07-style single commit) — a renamed pool orphans
mid-flight claims exactly like the strategy flip did (§R6-Q4-2), and in the (d)/(c) lanes
the wave additionally owns the lane switch itself (driver install / squat entry).

### R7-Q5 — Owner item 5 facts: app-template 5.0.1 conversion of charts/amd-gpu — VERDICT: converts cleanly

Vendored artifact inspected by unpacking `charts/radiance/charts/app-template-5.0.1.tgz`
(same bytes as the llama-swap/vllm copies) into /tmp — line refs below are the extracted
`app-template/` tree (schema = `values.schema.json`; classes =
`charts/common/templates/classes/*.tpl`; pod spec lib =
`charts/common/templates/lib/pod/_spec.tpl`). The device plugin's actual requirements,
from the vendored upstream-verbatim template (`charts/amd-gpu/templates/
deviceplugin-daemonset.yaml`, [repo read]): DaemonSet + args trio incl -v=5 +
**three hostPath volumes** (`/var/lib/kubelet/device-plugins`, `/sys`,
`/var/lib/amd-metrics-exporter` type DirectoryOrCreate) + `priorityClassName:
system-node-critical` (line 29) + tolerations + imagePullSecrets + nodeSelector (gated
off) + container securityContext (drop-ALL, lines 47-48/values 83-87) + resources.
**No hostNetwork, NO containerPort anywhere** — the brief's "port 9999" premise does not
exist in the ROCm plugin: registration is the unix-socket handshake
(kubelet.sock + the plugin's own `<name>.sock`) written INTO the
`/var/lib/kubelet/device-plugins` hostPath by kubevirt dpm; `/dev/kfd`+`/dev/dri/*` are
NOT mounted by the plugin pod at all (Allocate hands device nodes to kubelet at container
creation, plugin.go verified [R7-S3]; the PR #246 design note — naming reads /sys, no
/dev — stands). RBAC + ServiceAccount exist ONLY behind `labeller.enabled` (rbac.yaml:2,
serviceaccount.yaml:2 — false today), so the converted chart needs zero RBAC now.

Key-by-key expressiveness (schema/line → values key):

| need | app-template 5.0.1 expression | cite |
|---|---|---|
| DaemonSet | `controllers.<name>.type: daemonset` (enum deployment/statefulset/**daemonset**/cronjob/job; class template exists, 47 lines) | tgz values.schema.json:1750 (`const: daemonset` in a oneOf), :1886 (enum list); classes/_daemonset.tpl |
| args incl strategy | `controllers.<name>.containers.main.args` (array-of-string or string; `command` likewise) — restated trio + `-resource_naming_strategy=product` + `-v=5` all plain list items | tgz values.schema.json:3247 etc. (args under container/defaultContainerOptions/initContainers) |
| image + pullPolicy | `containers.main.image.{repository,tag,digest,pullPolicy}` | schema image block (same container object) |
| hostPath /sys, kubelet dir, health dir | `persistence.<vol>.{type: hostPath, hostPath: /sys, hostPathType: …}` — hostPathType docs list "DirectoryOrCreate, Directory, FileOrCreate, File" — then `globalMounts`/`advancedMounts` (mountPath, `subPath` in schema) | tgz values.schema.json:12518-12522; WORKING PRECEDENT: charts/generic-device-plugin/values.yaml:54-63 (type hostPath /var/lib/kubelet/device-plugins + /dev + configMap) [repo read] |
| SA + ClusterRole binding | `serviceAccount.<name>` (top-level) + `controllers.<name>.serviceAccount.{name,identifier}` + `rbac.roles.<name>.{type enum Role\|ClusterRole, rules[]}` + `rbac.bindings.<name>.{type RoleBinding\|ClusterRoleBinding, roleRef{name,kind,identifier}, subjects[]}` — class templates _serviceAccount/_role/_rolebinding exist | schema (serviceAccount/rbac properties, enums as walked); needed ONLY if the labeller ever returns |
| tolerations | `controllers.<name>.pod.tolerations` (or defaultPodOptions.tolerations) — CriticalAddonsOnly/Exists is plain pass-through | values.schema.json:1238/3080; lib/pod/_spec.tpl:74-75 |
| hostNetwork? | `pod.hostNetwork` exists (schema:918/2760; _spec.tpl:28 renders it, default false) — **not needed** (no ports) | |
| priorityClassName | `pod.priorityClassName` — `system-node-critical` plain settable | values.schema.json:975/2817; _spec.tpl:12-13 |
| updateStrategy | **GAP**: for DaemonSets common 5.0.1 renders NO `updateStrategy` (`controller.strategy` docs: "DaemonSets … ignore this field"; updateStrategy appears only in _statefulset.tpl:40; rollingUpdate handling in _deployment.tpl:47/_statefulset.tpl:42). Today's chart value `dp.updateStrategy: RollingUpdate/maxUnavailable:1` (charts/amd-gpu/values.yaml:45-48) EQUALS the k8s API default, so the rendered DS is behaviorally identical; a future OnDelete/maxUnavailable≠1 would need `rawResources` or an upstream ask | schema strategy description; template greps |
| securityContext/resources/imagePullSecrets/nodeSelector | `containers.main.securityContext` (privileged/capabilities/allowPrivilegeEscalation all in schema), `containers.main.resources`, `pod.imagePullSecrets`, `pod.nodeSelector` | schema (as walked) |
| naming/labels of objects | `global.nameOverride` + `persistence.<name>.forceRename`/prefix/suffix + container `nameOverride` — see strain below | schema global block |

**Strains (both manageable):**
1. **Object-name identity** (D19's byte-pin): upstream hardcodes
   `amd-gpu-device-plugin-daemonset` / container `amd-gpu-dp-cntr` / selector
   `name=amd-gpu-dp-ds`; app-template derives names from `global.nameOverride` +
   controller identifier (+ labels `app.kubernetes.io/*`), so the conversion RENAMES the
   DaemonSet object. That is fine IF it lands as the same Application's one-sync swap
   (Argo prunes the old DS + creates the new; plugin gap of seconds; running GPU pods
   unaffected — §R6-Q4-4 allocation law, and the D21 per-cluster shield keeps the
   gpu-cluster on the external chart). The byte-pin's purpose (orphan-free repo→git
   source flip) is served by keeping `global.nameOverride: amd-gpu` + a controller named
   to get the closest stable prefix; tests that grep object names
   (amd-gpu-naming.sh, test_provenance window-join) re-pin in the conversion commit.
2. **updateStrategy** — see table row: gap today is behaviorally null; document it in the
   conversion's DECISIONS line.
Everything else the plugin pod is (hostPaths, args, priority, tolerations, drop-ALL) is
first-class app-template; the repo already runs the *same pod shape* — a device plugin
with kubelet-dir hostPath + configMap + args + env — through app-template 5.0.1 in two
clusters (charts/generic-device-plugin; caveat: that chart leaves the controller at the
schema default `deployment` — single-node clusters; the amd-gpu conversion sets
`type: daemonset` explicitly, which is schema-supported and class-rendered)
[repo read]. Conversion additionally delivers owner item 4 (the `lbl:` key dies with the
vendored values file) and kills the D19 refresh-debt line (first-party chart, upstream
PR #122 staleness becomes irrelevant).

### R7 — Contradictions & corrections to §R6

- **§R6-S8 chart-values quote was master, not the v1.0.1 tag**: `deviceClass.
  extendedResourceName: amd.com/gpu` does NOT exist at tag v1.0.1 (tag values.yaml:19-21
  = create only; tag deviceclass.yaml renders the class WITHOUT extendedResourceName) —
  it is a master-only addition (master values.yaml:28 + conditional render, incl. an
  AutoPartition second-class variant). The mapping still works with the pinned v1.0.1
  driver because it is control-plane-side, but at v1.0.1 the chart cannot render the
  named class — the (d) lane must hand-ship the DeviceClass YAML [R7-S7,S8].
- The brief's "any supported per-product name/prefix at .12" question resolves harder
  than §R6 assumed: not only is there no override — the prefix (`gpu-`) AND domain
  (`amd.com`) are code constants, so even the table-mount hack cannot express a
  prefix-free name. §R6's "the only in-repo filter is WHICH names it advertises"
  stays true, with "which names" narrower than anyone hoped.
- "amd.com/gpu-ai-pro-r9700: \"1\"" — the rendered claim line the owner annotated is
  correct per §R6-Q1's sanitizer port; nothing in §R6 needs revision for item 3's
  factual basis.

### R7 — Adjacent (cheap, worth recording)

- The owner's "-1" reads like "one device" or a run-ordinal; both are true of the pool
  already (each bucket holds exactly one card on this node) — a one-line comment beside
  the claim in charts/radiance/values.yaml can carry the intent the name cannot.
- If the upstream ask (b) is filed, the two credible shapes upstream would weigh:
  (i) a `-resource_name_prefix`/-`-domain` flag pair (breaks dpm namespace contract,
  unlikely), or (ii) an override side-map file consulted by `ResourceName` before the
  table (matches the code's existing seam — products.Name lookup). Shape (ii) is the one
  to argue for; it would live next to IDsPath as a const-defaulted path — no precedent
  exists yet, so treat as speculative.
- D19's governance note + Deferred "upstream amd-gpu chart refresh" line both become
  moot if owner item 5's conversion lands (first-party chart replaces the vendored fork;
  refresh policy replaced by app-template dep bumps via renovate, already the repo norm).

### R7 — Open questions

1. **Owner call on the literal string**: keep `amd.com/gpu-ai-pro-r9700` (recommended —
   within the Option-1 ruling; verdict NO on customization), or accept `amd.com/gpu-r9700-1`
   via the unsupported table-mount hack (NOT recommended), or switch lanes to (d)
   DRA-extendedResourceName / (c) squat for the exact `amd.com/r9700-1` — both reopen
   decisions D18/B1 settled; research flags (d) is the only exact-string lane with
   determinism.
2. On-target confirmation IF (d) ever runs: `DRAExtendedResource` beta on-by-default at
   the lab's k3s v1.36.5 (docs say beta 1.36; types.go `+featureGate` comment verified —
   the k3s gate default is a C06-style receipt, not a claim).
3. File the upstream ask (b)? (No duplicate exists today; recommended yes, independent of
   the lane chosen.)
4. Item 5 conversion mechanics (object-name target for `global.nameOverride`/controller
   identifier, and whether the updateStrategy gap is acceptable as-is) — plan-level call
   owed when the conversion chunk is written.

### R7 — Sources (accessed 2026-11-12)

| # | URL / path | What it is |
|---|---|---|
| R7-S1 | raw.githubusercontent.com/ROCm/k8s-device-plugin/v1.31.0.12/cmd/k8s-device-plugin/main.go (+ master same path) | full flag surface: -pulse, -resource_naming_strategy, glog trio; LoadProductIndex(IDsPath) call site; master identical |
| R7-S2 | same …/v1.31.0.12/internal/pkg/naming/naming.go | DefaultResource "gpu", maxResourceNameLen 63 "after amd.com/", SanitizeResourceName rules, ResourceName product branch, ResourceList |
| R7-S3 | same …/v1.31.0.12/internal/pkg/naming/products.go + …/internal/pkg/plugin/plugin.go + master plugin.go | IDsPath const; filler set + pro/rx note; **dropWords returns DefaultResource+"-"+…** (the inescapable gpu- prefix); collision→qualify; GetResourceNamespace()=="amd.com" hardcoded; bucketDevices/Allocate; no Getenv master or tag |
| R7-S4 | same …/v1.31.0.12/internal/pkg/amdgpu/amdgpu.go | sysfs-only discovery; pciHexAttr; zero env/config inputs |
| R7-S5 | same …/v1.31.0.12/Dockerfile + docs/user-guide/configuration.md | amdgpu.ids baked via COPY; CMD trio; docs naming section: table-derived names, exit-if-table-unreadable, no custom-name surface |
| R7-S6 | api.github.com/repos/ROCm/k8s-device-plugin/contents/internal/pkg/naming?ref=v1.31.0.12 AND ?ref=master | naming package = 4 files at both refs — no override module anywhere in flight |
| R7-S7 | raw.githubusercontent.com/ROCm/k8s-gpu-dra-driver/v1.0.1/helm-charts-k8s/{values.yaml,templates/deviceclass.yaml} | tag DeviceClass renders selectors only, NO extendedResourceName (correction to §R6-S8) |
| R7-S8 | raw.githubusercontent.com/ROCm/k8s-gpu-dra-driver/master/helm-charts-k8s/{values.yaml,templates/deviceclass.yaml} | master adds deviceClass.extendedResourceName default amd.com/gpu, conditional render, AutoPartition spx-class note |
| R7-S9 | api.github.com/repos/ROCm/k8s-device-plugin/issues?state=open&per_page=100 (full list fetched 2026-11-12) | no custom-naming/prefix/domain issue exists; #215 amdgpu.ids refresh automation OPEN; #45 isolation OPEN; PRs #243/#247/#214/#213/#212/#191/#189/#122/#38 open |
| R7-S10 | kubernetes.io/blog/2026/05/07/kubernetes-v1-36-dra-136-updates/ | "Extended resource support (beta)" — classic extended-resource requests served by DRA |
| R7-S11 | kubernetes.io/blog/2026/09/03/kubernetes-v1-37-dra-updates/ | KEP-5004 family GA 1.37; "extended resource name set directly on a DeviceClass", no pod claims; timeline alpha 1.35/beta 1.36 |
| R7-S12 | raw.githubusercontent.com/kubernetes/kubernetes/release-1.36/staging/src/k8s.io/api/resource/v1/types.go | DeviceClassSpec: Selectors (class-side CEL/label, "each selector must be satisfied by a device claimed via this class"), ExtendedResourceName *string (format k8s-extended-resource-name, unique per cluster, +featureGate=DRAExtendedResource, "This is a beta field") |
| R7-S13 | raw.githubusercontent.com/squat/generic-device-plugin/main/README.md | `--domain` flag (default devic.es) + arbitrary device names → literal `amd.com/r9700-1` expressible |
| R7-S14 | repo reads (branch cf-143-feat-radiance-replaces-strata): charts/radiance/charts/app-template-5.0.1.tgz (unpacked: values.schema.json lines 918/939/966/975/1238/1750/1886/2760/2781/2808/2817/3080/3247/12518-12522; charts/common/templates/classes/_daemonset.tpl 47 lines, no updateStrategy; lib/pod/_spec.tpl:10-31,74-75), charts/amd-gpu/{Chart.yaml,values.yaml,templates/{deviceplugin-daemonset,rbac,serviceaccount}.yaml}, charts/generic-device-plugin/{Chart.yaml,values.yaml}, tests grep of the two pool names | conversion key inventory + blast-radius list; DECISIONS.md D18/D19/D21 + owner-review items 3-5 lines 161-173/174-189/202-237/272-316 |

---

## §R8 — does 110 GiB cover fn at 8×200K? (owner capacity question)

Owner ask 2026-11-13 (verbatim): "I would also like you to check whether the 110Gi is
enough for the 200K context for the model I'm running." Object: shipped
`guaranteedMemoryGi: 110` (D29) + the serve recipe (pool 43000 / kv-resident 32768 /
8×200000 / spec 3 / chunk 4096 / ngram disk / headroom 96, values.yaml:138-154).
Authorities read this round: RQ1, RQ4/RQ5, Serving envelope, §R6/§R7, EXPLORE §D4/§D6,
DECISIONS D28/D29, runbook step 6, TP2 doc §7-§9/§11, the two boot receipts quoted in
the launch (owner captures 2026-11-13). Repo lines [repo read]; kernel semantics
[R8-S1][R8-S2]; earlier external evidence keeps its [S#] keys.

### R8 VERDICT (one sentence, then the arithmetic)

**YES — 110 GiB covers the fn-TP1 8×200K case: the 200K×8 cost is NOT what the host is
paying for (it is funded ON-CARD at 4.49–4.51 GiB per the engine's own "worst case"
line, and the host-side mirror for it is an EAGER boot-time reservation already inside
the printed `pinned by this process 71.04 GiB`), leaving 38.96 GiB under the 110 cap
against the documented growth allowance of ~21 GiB (D28's own basis for the 96 rung) —
steady-state PROVEN, peak-sufficient vs every known term with ~14 GiB margin over the
receipt-anchored 96, and the ONLY open term is what the never-yet-run 8-session gate
(runbook step 6) can surprise, which is exactly what the number now buys slack for.**
The counter-intuitive worry — "a bigger cgroup starves the page cache the n-gram disk
reads want" — is REFUTED on mechanism: the disk tier is O_DIRECT [S2 §4.3; boot B's own
line "a direct read of one returned the file's bytes"], so the 47.68 GiB table never
enters page cache at all; the raise is **orthogonal to the disk path, helps boot
(refuses), and costs only node slack** (9.80 GiB scheduler-free strata-down; strata
restore co-residency dead at 110 by design — D29's either/or).

### R8-Q1 — Where 200K actually costs memory (the two homes, separated)

**(i) ON-CARD — the 200K worst case is funded there, not in RAM.** Boot B printed
`kv cache 4.49 GiB a card: 1600000 tokens, 8.0 sessions at 200000` (= 8×200,000 exactly)
with "1.72 GiB of it per-sequence state; up to 1.23 GiB lent to the experts while no
request holds it", and the VRAM budget line `kv 4.51 = 19% … "backs 8 sequences all at
200000 tokens at once, which is the worst case"` inside elastic 23.89 of claimable 29.30
on the 31.86 usable card (launch receipt; static 5.40, experts 17.76 = 74%, prefill
staging 1.63). Implied on-card rate = 4.49 GiB ÷ 1.6M tokens = **2.94 KiB/token**
(paged part (4.49−1.72) → 1.81 KiB/token + 0.215 GiB/sequence of delta-net state). This
is the receipt the RQ1 "pin to the receipt, not to a per-token figure" verdict demanded
[RQ1 Serving envelope] — and it also sits well BELOW the doc's 7.32 KiB/token worked
example and the field's 30–60 KiB band [S2 §4.3][S8][S16]: the fp8 paged groups on this
build cost ~3 KiB/token on-card. **Conclusion: "200K context" does not add host RAM;
`--kv-resident` moved the SPARSE QSA group to RAM, and that host copy is the host cost.**

**(ii) HOST-SIDE — the reservation arithmetic.** RQ1's law: the kv-resident "host copy
reserved max-num-seqs × max-model-len however short the requests" [S2 §4.4.1] — eager,
at boot. Boot B's printed sum decomposes at the receipt's own terms:

```
pinned (printed, boot B, cgroup 94.00, SERVED)   71.04 GiB
  host pool 42.70 (weights: expert_tiered pins experts there;
  "experts-from-host 41.52 GiB … cross PCIe" per the same report)
  + placement-flag items 1.18 (token embedding, encoder towers, drafter experts)
  + activation/arena 2.00 (D28 term)
  + step staging (D28: folded in the observed sum)
  + --kv-resident host mirror … THE RESIDUAL
residual  = 71.04 − 42.70 − 1.18 − 2.00          = 25.16 GiB  → 16.1 KiB/token
upper bound (if arena/placement are inside pool) = 71.04 − 42.70 = 28.34   → 18.1 KiB/token
```

Reconciling the three booked rates at 8×200K = 1.6M tokens:

| rate | source | 1.6M-token mirror | fits boot B? |
|---|---|---|---|
| ~12 KiB/token | RQ1's doc-derived figure (two 262k convs at 3.22 GiB/card → 12.9) [S2 §4.4.1] | 19.3 GiB | **NO** — pool+placement+arena+19.3 = 65.2 ≠ 71.04; leaves 5.9 GiB UNBOOKED against the print; and 65.2 > 64.00 ⇒ boot A still dies, so boot A does NOT discriminate — boot B falsifies the 12 rate as an envelope (D28 records exactly this slip) |
| ~16–18 KiB/token | **boot B receipt (derived above)** | 25.2–28.3 GiB | YES — by construction (it is the residual) |
| ~20 KiB/token | D28's booked envelope ("shipped 1.17.0 books ≈20 KiB/token (~32 GiB at 8×200K)") | 30.5–32 GiB | YES as CONSERVATIVE cover — over-books the residual by 2–5 GiB; D29's ladder arithmetic (110 − 71.04 = 38.96) rides the printed sum, so the over-book is margin, not a defect |

**Which the live receipt supports: the truth is ~16–18 KiB/token (boot B); the 12
RQ1-carried figure UNDER-reserves (~6 GiB short of the print) and the D28 ~20
over-reserves by a safe 2–5 GiB. Plan must keep using printed sums, not rates (RQ1's
verdict line stands: "don't plan off any per-token figure; the receipt prints it").**
Boot A (64.00 cgroup) is the EAGERNESS proof: `pinned 43.18` at the pre-streaming
print [D28(1)] = pool + fraction, then OOM during the mirror reservation — the host
copy was being reserved at startup, with zero sessions arrived. So the 8×200K host cost
is present from t=0, not at peak: steady state and "all sessions short" cost the SAME.

### R8-Q2 — Verdict on 110, term-by-term (a)/(b)/(c) growth enumeration

Boot-state (already inside the printed 71.04, class (a)): expert pool 42.70; **kv-resident
mirror for the FULL 8×200K worst case** (reserved max-num-seqs × max-model-len
however short — boot A/B prove eager); placement 1.18; activation/arena 2.00; step
staging as printed. Add these OUTSIDE the print (class (b), with estimates):

| term | estimate | basis | inside 110 − 71.04 = 38.96? |
|---|---|---|---|
| full-8-session prefill staging + slot fill growth as contexts actually reach 200K | **≈21 GiB** — this is D28's OWN allowance (96 = 71.04 + 4 + ≈21 "for full-8-session prefill staging") | [D28(3); runbook step 6] | YES (+ ~14 spare beyond the 96-rung budget) |
| checkpoint-slot tier (linear-state snapshots ride HOST PINNED memory; ~113.5 MiB/slot; RQ1 read ≈8.87 GiB at 8 seqs; auto-cap 1/8 host RAM ≈ 15.6 GiB) | ≤8.9–15.6 GiB, likely INSIDE the 21 GiB allowance already (D28's 96 arithmetic had to cover the same arrivals) | [S2 §4.8; RQ1] | YES (contained in prior row or its surplus) |
| io_uring disk-row cache | ~0.085 GiB (the table's only resident host footprint on disk placement) | [S2 §4.3] | trivial |
| kv-streaming miss bursts (resolves/lookups/misses) | ring is ON-CARD (32,768-token ring/group; boot B ring 16416 blocks; miss class 6,357/1,357,869 ≈ 0.4% per request end) — misses cost PCIe TIME, not host bytes | launch receipt [R8-S7] | no growth term |
| speculative-decode buffers (MTP-3) | on-card, inside printed kv/elastic ("1.72 GiB per-sequence state" incl.); host-side drafter experts already in placement 1.18 | boot B budget lines | (a) |
| demotion-burst class (Wilde: idle sessions demote PINNED in a 9.4 GiB/2 s burst) | **structurally OFF on this profile** — the burst is the PREFIX-CACHE TIER's demotion mechanism, and the tier is force-off while a group streams [S2 §4.4.1; RQ1]; it RE-ENTERS only if the last-resort ladder swap ships | [S9][S2] | N/A today (re-check on swap) |
| HIP/driver drift, tokenizer, misc anon | unquantified; boot B implies ~8–9 GiB node-wide non-pod + pod anon already outside pinned | boot B RAM 125.08/45.57 | fits; bounded small |
| **TRUE PEAK: 8 simultaneous 200K-filled sessions decoding at once** | **UNKNOWN (class (c))** — no receipt exists; boot B served with single-request traffic (cache 0 on every request; 5.1/12.4/19.3 tok/s at gen 123/896/717); the runbook step-6 gate is the datum | [runbook step 6] | this is what step 6 decides |

**Verdict: SUFFICIENT at steady state (margin 38.96 GiB vs the engine's own ≥4 GiB-free
rule — D29 quote "110 − 71.04 = 38.96 ≥ 4 ✓ with margin"; values.yaml:52-59);
SUFFICIENT at every KNOWN peak (71.04 + 21 allowance + 4 rule = 96.04 ≤ 110, 14 GiB of
documented-rung surplus beyond C12's 96); TIGHT only against (c)-class surprises beyond
~39 GiB of simultaneous growth — implausible given the allowance D28 priced for exactly
the arrivals (21 GiB) but unproven until step 6 runs. The evidence-backed "comfortable"
number: 110 already IS the comfortable number (96 was "sufficient", 110 = 96 + burst
slack, per D29 "+14 GiB prefill-burst headroom"). What was NOT ever sufficient: 64
(boot-A defect class — below printed budget, D28 class law: "a limit below the printed
budget is a defect, not a ladder step"); 94 (boot B) served but sat BELOW the 96
arithmetic, i.e. inside the allowance it had ~0 of the priced burst cover.**

### R8-Q3 — The node-level tension, checked not assumed: VERDICT = orthogonal-to-hurtless for the disk path, helpful for boot, paid in node slack

The worry's shape: pod 110 of a 125.08 GiB node ⇒ less host page cache ⇒ the 4 KiB-span
n-gram reads slow. Each link, with the deciding facts:

1. **The n-gram disk tier does not USE page cache.** `--ngram-placement disk` =
   "streamed from the .rad via a host io_uring row cache (~85 MiB, **O_DIRECT**, ~half
   first-seen rows)" [S2 §4.3]. O_DIRECT bypasses the page cache into user buffers; boot
   B's own line says the direct read "returned the file's bytes" (and the owner's dd
   measured 3.42 GB/s `iflag=direct` on the very btrfs PV [D6.5]). The btrfs alignment
   story (statx STATX_DIOALIGN unreported → engine reads in 4096-byte spans [D6.5;
   man-pages 6.19 statx]) is about SPAN GRANULARITY, not about losing directness. So the
   47.68 GiB table resident anywhere on the node ≈ 85 MiB + in-flight spans.
   **Proof-from-receipt (arithmetic, not doctrine):** boot B printed node-wide
   `RAM 125.08/45.57 available` — 125.08 − 45.57 = 79.51 GiB total used, vs 71.04 pod
   pinned ⇒ only ~8.5 GiB of everything-else, INCLUDING any cache. If the table were
   page-cached, `available` would read near zero. The 47.68 GiB "mapped" is
   address-space mapping (weights-by-tier line), NOT residency. The "110 squeezes the
   cache the table reads need" premise is therefore falsified at the first link.
2. **cgroup accounting anyway:** memcg charges page cache + anon to the cgroup that
   instantiates the pages, and mlocked anon lands unevictable — the pod's own disk-path
   footprint (~85 MiB ring + touched buffers) is charged INSIDE the 110 cap, where it
   fits trivially [R8-S1 "Memory Ownership" + tracked-usages list]. Raising the cap does
   not re-route any charge.
3. **memory.high / memory.max / memory.reclaim pressure:** Kubernetes maps the container
   LIMIT to the cgroup v2 HARD limit `memory.max` (OOM-kill-at-breach semantics
   [R8-S1: "If a cgroup's memory usage reaches this limit and can't be reduced, the OOM
   killer is invoked in the cgroup"]); `memory.high` is the THROTTLE knob and is left at
   "max" (= disabled) by kubelet (owner one-liner to confirm in R8-Q4's capture:
   `cat …/memory.high` expecting `max`); `memory.reclaim` is manual, unused. A cgroup's
   usage near its own max triggers reclaim INSIDE that cgroup — the pod has ~no
   reclaimable memory inside (pool+mirror+mlock ⇒ unevictable [R8-S2: mlock "preventing
   that memory from being paged to the swap area"; resident "guaranteed to stay in RAM";
   same physics the engine README quotes: "that nothing else can use and the kernel
   cannot swap out" [S1]) — so a bigger max neither evicts host cache nor gets evicted;
   it just defers the OOM boundary. Global host page cache shrinks only under GLOBAL
   pressure — and this pod's actual usage is profile-driven (~75–92 class), NOT
   cap-driven: the same 71.04 pinned at cgroup 94, and the mirror reserved to the same
   size at 110 (boot A/B evidence). **The cap number does not change what the engine
   allocates.**
4. **The real node cost of 110 is scheduler arithmetic, already ruled:** 110 + 4.125
   router + 1.158 floor = 115.28 ≤ 125.08, 9.80 GiB free strata-DOWN; strata restore-back
   (64 request) can never co-reside (180.3) — D29's stated inversion: the cutover is a
   real either/or at 110 (it already was at 96's 166.3). Node MemAvailable at boot B was
   45.57 with pod-used ~75; at 110 nothing is consumed differently — the cap itself
   commits nothing beyond the scheduler reservation (Guaranteed reserves REQUEST = limit
   for scheduling; physical pages appear only as the profile pins them).
5. **Swap:** 425 MiB already in use (boot B) of the node's 2.15 GiB swap [node object,
   D6.2-era] cannot BE the pinned tier (mlock forbids swap [R8-S2]) — it is the
   non-pinned anon (misc host daemons, the pod's small swappable anon). With zram
   masked [S9 law, host-prep] and the engine's own `note swap` class line printed, the
   honest read: swap is a symptom to watch (memory.swap.current), not a 200K/8-session
   risk driver — the whole profile is deliberately unswappable by construction.
6. **Compaction/failure counters:** compact_stall 117,859 / compact_fail 47,681 /
   allocstall_movable 116,143, THP always/madvise, HugePages_Total 0, buddyinfo Normal
   order-6 = 112 blocks (~28 MiB) [launch receipt / owner capture]. The pinned ~71 GiB is
   a long-lived movable-zone population — exactly the class that ages into order-N
   starvation, and the counters show the node already struggles for contiguous blocks
   (attribution radiance-vs-router-vs-strata-lifetime is UNVERIFIABLE from one snapshot —
   flagged honest). Decisive for the cap question: **the pinning footprint and order
   behaviour are IDENTICAL at 94 and 110** (same profile pins the same bytes) — raising
   the cap neither causes nor cures fragmentation; what mitigates the class is booting
   radiance FIRST after a reboot (fresh memory; boot B's success pattern) and treating
   restart-after-long-uptime as the risk moment (step-6 capture includes the
   buddyinfo/compact deltas). A THP/madvise host policy or pool-rewrite lane is TP2-era /
   host-prep territory, not a C12 scalar.

**Q3 verdict: raising 94→110 HELPS (the boot-refusal margin; the (b)-allowance cover),
HURTS ONLY node slack (strata co-residency — already the ruled either/or), and is
ORTHOGONAL to the n-gram disk path (O_DIRECT never touches the cache it was going to
squeeze) — the launch's counter-intuitive tension does not exist on this profile.**

### R8-Q4 — What to measure next (8-session gate, runbook step 6, NOT yet run)

All reads below are owner-executed-host / log-capture prose (no exec from here).
Boot-time engine startup report on the 110/110 Guaranteed roll (the roll also restores
QoS from today's Burstable 64/94 hand-edit — D29(4)):
- `pinned by this process X GiB` → **PASS 71 ≤ X ≤ 78** (drift allowance ~10% over boot
  B); **X > 106 ⇒ STOP**: re-sum the printed tiers before ANY scalar edit (budget-line
  class law D28(6) — the limit below the printed sum is a defect).
- `weights by tier … host pool` → expect 42.70 class; `the host pool holds the 1.18 GiB
  … placement` → expect ≈1.18; `kv cache X GiB a card: 1600000 tokens, 8.0 sessions at
  200000` → expect ≥4.49 and "backs 8 … at once" (the on-card 200K-worst funded);
  `RAM 125.08/Y available` → expect Y ≥ 30 at boot; the context lines (memlock 8 MiB
  note, link WARN class, governor) ride as host state, not pass/fail here.
Gate (8 concurrent sessions driven to 200K-class depth THROUGH the peer hop, per runbook
step 6's skeleton; PASS = "eight admitted without refusal-class errors and decode
steady" verbatim), capturing DURING and at peak:
- host, pod cgroup (path via `crictl inspect` of the serve container): `memory.current`
  **PASS ≤ 100 GiB at peak**; `memory.peak` after the gate **≤ 100** (reset-by-write is
  available [R8-S1]); `memory.events(.local)`: `max=0`, `oom=0`, `oom_kill=0` ANY non-zero
  = the cap bit ⇒ record and ladder; `memory.stat` keys — `anon` (≈ pinned class),
  **`file` should stay SMALL (≤ ~1 GiB; a growing `file` would mean something IS
  buffering the pack — falsifier for the O_DIRECT assumption above, investigate before
  believing any cache-squeeze story)**, `unevictable` ≈ the pinned sum (cross-check of
  mlock accounting), `workingset_refault_file` near 0; `memory.swap.current` ≤ ~1 GiB;
  `memory.high` = `max` (kubelet-mapping confirmation one-liner).
- host: `/proc/meminfo` — `MemAvailable` **≥ 8 GiB at gate peak** (floor class),
  `AnonHugePages`, `Committed_AS` (≤ ~135 GiB sanity), `SwapCached`;
  `/proc/buddyinfo` + compact_stall/compact_fail/allocstall_movable DELTAS around the
  boot and around the gate.
- engine: `/stats` running/waiting during fill; per-request-end kv-streaming counters
  (today class: 797 resolves / 1,357,869 lookups / 6,357 misses ≈ 0.4% [receipt]) —
  miss% exploding under 8×200K = ring pressure → record for the ladder; decode tok/s per
  stream vs today's single-stream band (5.1/12.4/19.3 at gen 123/896/717) — acceptance is
  steady, not a rate; note the half-width Gen3 link defect (~142 class prefill) is a
  SEPARATE open lane (§D6.6) and will mask gate speeds — do not ladder the profile for a
  link defect.
Ladder, ONLY if the gate refuses (D17 "never preemptively soften — the receipt decides";
runbook step 6's own order, ONE scalar per rung, `guaranteedMemoryGi` never below
printed-sum + 4):
1. `hostPoolMib` 43000 → 40000 → 36000 — frees host pins 1:1 (42.70 class ↓); cost:
   experts spill back onto the card, kv elastic room shrinks — read the `kv cache` and
   `experts-from-host` receipt lines after the change [runbook ladder-DOWN "pool first"].
2. `maxModelLen` 200000 → 131072 → 65536 (8 seqs) — mirror ↓ proportionally (−~8.5
   GiB/−17 GiB at the receipt rate); cost: forfeits the 200K promise; catalog
   `limit.context` rows MUST re-pin in the same change (true-axis law).
3. `maxNumSeqs` 8 → 4 — halves the reserved mirror (RQ1 reservation semantics); cost:
   CONCEDES the 8-session target — a redefinition = owner call recorded.
4. LAST resort, explicit owner sign-off: the mutually-exclusive swap — drop
   `--kv-resident 32768`, add `--prefix-cache-mib 4096` (the v1.17.0 4-seq published
   recipe, pool backs ~301K ≈ 1.5×200K [S3][RQ1]) — host ↓ ~25 GiB, cost: the 8-live
   shape is gone AND Wilde's pinned-demotion-burst class RE-ENTERS (tier demotions land
   pinned, 9.4 GiB/2 s precedent [S9]) — with `--prefix-cache-mib 0` as the escape hatch.
(Recorded separately, NOT a memory rung: the init CPU 200m→1000m knob (D28(4)) — staged
hash wall-clock only.)

### R8-Q5 — Cross-check vs the TP2 follow-up (doc §7/§9/§11; RQ4/RQ5)

The TP2 fn recipe [TP2 §7, verbatim flags]: `--tp 2 --tp-wire wht6 --max-num-seqs 8
--max-model-len 200000 --placement expert_tiered --host-pool-mib 12288 --gpu-headroom-mib
96 --kv-cache-dtype fp8 --prefix-cache-mib 4096 --num-speculative-tokens 3
--max-num-batched-tokens 2048`.
- **Does 8×200K at TP2 change the host answer? YES — it shrinks it ~3×**: pool is
  per-rank (2 × 12288 MiB ≈ 24 GiB [TP2 §7]), `--kv-resident` OUT ⇒ the ~25–30 GiB
  mirror disappears, prefix tier 4 GiB back in (exclusivity: one lever or the other,
  never both [RQ1; TP2 §7]), placement/arena ≈3 ⇒ host-pinned class **≈ 30–35 GiB** vs
  today's 71.04 + 21. Production witness: llmkube runs TP2 at full 262144 with pool 8192
  on a 62 GiB host at **request 40 / limit 48 GiB** [S11] — i.e. the TP2 pod-class is
  ~half of today's 96-rung arithmetic.
- The CARD question stays a receipt question at TP2 too: Wilde's Gen4-class TP2 backed
  "~15.7 GiB pool ≈ one 262k whale or ~4×64k" [S8] — 8×200K live at TP2 is not claimed
  by any witness; TP2 §8 pre-registers exactly that as an open receipt item ("pin to the
  startup receipt, not to any per-token constant" — same law).
- **Is the 110 single-card decision consistent with the TP2 path, or does it strand
  anything? Consistent, nothing stranded**: 110 is the SUPERSET envelope until TP2's own
  receipts re-pin the scalar (TP2 §11's adoption step rewrites `hostPoolMib` and the
  serveArgs anyway; the class law then re-reads the printed sum before the new scalar
  ships — D28(6)). The one asymmetry to record for the cutover ticket (Deferred,
  owner's): strata restore-back is dead at 110 (180.3 > 125.08), but a TP2-era radiance
  at the llmkube 40–48 class would make 48 + 64 + 6.3 ≈ 118.3 ≤ 125.08 again
  *arithmetically possible* — TP2 relieves RAM pins (not the pin-cap formula, whose
  120.6-class cap both cards' pools still respect [S1; TP2 §9 "TP2 relieves VRAM
  contention, not the RAM pin ceiling" is about per-process sums, and two ranks still
  pin against the same cap]). Flag: co-residency re-opening is a cutover-ticket
  consequence of TP2, not a reason to hold today's number down.
- TP2 does NOT rescue the RAM-ngram tier either way (71.04 + 47.68 = 118.72 > 110 is a
  single-card profile statement; TP2's mirror-free shape would make the tier arithmetic
  `24 + 47.68 + ≈3 = 75` — interesting but out of scope; rides TP2 §10's host-prep list).

### R8 — Honest uncertainty list

1. **Class-(c) peak** — no receipt of 8 simultaneous 200K-filled sessions exists ANYWHERE
   in the corpus (RQ1's contradiction section: "nobody in the fetched corpus serves
   fn-TP1×8-long-sessions on one R9700"); 110's sufficiency at true peak is inference
   from the eager-reservation shape + D28's priced allowance, decided by step 6.
2. The residual method behind 16–18 KiB/token attributes the 71.04 minus known terms to
   the mirror; if `activation/arena`/`staging` interleave differently (terms overlap in
   the print — the parts sum to 77.88 vs the whole 71.04, so some terms double-count),
   the mirror could be as low as ~25 GiB — the (b)-term estimates would then shrink and
   the verdict stays sufficient (the cap margin only grows).
3. `file` growth inside the pod cgroup was predicted ~zero from O_DIRECT semantics; the
   gate capture is the falsifier (cheap, one key).
4. Compaction counters are host-wide and unattributable to radiance from one snapshot.
5. Boot A/B are DIFFERENT cgroups (64 vs 94) but the same profile — the 71.04 figure is
   valid at 110 only because the reservation is profile-driven (boot A/B comparison is
   the evidence, and it is ONE pair of boots on ONE build).
6. The engine's `pinned by this process` scope (VmLck-equivalent? includes arena?) is
   taken at face value from the print label; the cross-check is
   `unevictable`/`memory.current` vs the line (in Q4's plan).

### R8 — Implications for the plan (fold)

- D29's shipped 110 **survives the capacity review** — no change; the ladder does not
  re-open pre-gate ("the receipt decides", D17 law).
- Runbook step 6 is now the SINGLE load-bearing open gate for the memory question; its
  capture list should adopt Q4's keys (cgroup memory.peak/events/stat, /proc/meminfo,
  buddyinfo deltas) — a doc-round line, not a scalar.
- The per-token law restated with live numbers: plan off receipts (71.04), not rates
  (12/20) — already D28's class law; §R8 adds the on-card side: the 200K×8 KV worst case
  lives in VRAM (4.49 GiB), the host pays the EAGER mirror, so "more context" at this
  profile is nearly FREE in RAM terms beyond the reservation already made.
- TP2 doc §11's adoption step and the cutover Deferred row inherit this round's TP2
  numbers unchanged.

### R8 — Sources (accessed 2026-11-14)

| # | URL / path | What it is |
|---|---|---|
| R8-S1 | raw.githubusercontent.com/torvalds/linux/master/Documentation/admin-guide/cgroup-v2.rst (fetched full) | memory controller: tracked usages (page cache + anon + kmem + tcp), memory.max HARD-OOM semantics, memory.high THROTTLE (not OOM), memory.peak semantics (+reset-by-write), memory.events low/high/max/oom/oom_kill definitions, memory.stat keys (anon/file/unevictable/workingset_refault_*/swapcached), Memory Ownership = charged-to-instantiating-cgroup |
| R8-S2 | man7.org/linux/man-pages/man2/mlock.2.html (man-pages 6.19, 2026-02-11, fetched) | mlock: locked pages "preventing that memory from being paged to the swap area", guaranteed-resident-and-stay-in-RAM; RLIMIT_MEMLOCK/CAP_IPC_LOCK semantics (grounds D28's memlock-scope line) |
| R8-S3 | repo reads: .agents/notes/radiance-on-target-acceptance.md step 6 (lines 469-555: gate law, 110 arithmetic verbatim, ladder order) · radiance-second-gpu-tp2.md §7 (lines 169-211 recipe + per-rank math) §8 (213-231 envelope) §9 (233-256 second-lane) §11 (298-300 adoption scalars) · charts/radiance/values.yaml:30-66 (D29 block, 71.04 decomposition) :70-76 (lever/exclusivity) :90-123 (plugin facts post-D24) :131-154 (serveArgs) :279-299 (claim pair gpu-r9700-1) · DECISIONS.md D28 (lines 508-579) / D29 (587-663) · EXPLORE.md §D6.1-§D6.7 | ticket authorities read per the launch; shipped-state inventory |
| R8-S4 | boot A/boot B startup-report receipts + host capture quoted in the launch brief (owner, 2026-11-13; corroborated live-class by §D6.2's node figures 125.08 / pools gpu-r9700-1 + gpu-8060s + bare 0, Burstable 64/94 state, first-request 11.2 tok/s) | the primary evidence this round computed against |
| (inherited) | [S1][S2 §4.3/§4.4.1/§4.8][S3][S5][S8][S9][S11][S12][S14][S16][S19] per RESEARCH Sources table | engine docs (O_DIRECT disk tier, kv-resident exclusivity + reservation semantics, prefix tier + checkpoint slots, pin cap), shipped recipes, Wilde/bigcherry/llmkube field receipts, live node reads |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R8 appended)]
commands_run: [repo reads (RESEARCH RQ1/RQ4/RQ5/envelope, §R6/§R7 re-read; EXPLORE §D4+§D6 full; DECISIONS D28/D29 + D23/D24 rename block; charts/radiance values scalars/args/claims; runbook step 6; TP2 doc §1-§14 map + §7/§8/§9/§11 text; STATE.json chunk statuses C05-C12) => pass; webfetch kernel cgroup-v2.rst (master) => pass; webfetch man7 mlock(2) 6.19 => pass; arithmetic recomputations (on-card 2.94 KiB/token, mirror residual 16.1-18.1 KiB/token, 12/20-rate refit, 110 sums 115.28/38.96/96.04, TP2 ~30-35 class, 48+64+6.3=118.3) => pass; first mlock(2) proxy fetch failed (403) — re-fetched via man7.org => pass]
deviations: none — answered the five questions in order, read-only; no file written but RESEARCH.md (appended §R8). Where the launch invited a verdict beyond its framing, said so: the "20 KiB vs 12 KiB" reconciliation resolved to a THIRD figure (~16-18 KiB/token, the receipt-derived residual) with both booked rates kept as the safe-envelope and falsified-derivation respectively.
friction: the boot-B decomposition does not close exactly (parts sum 77.88 vs printed whole 71.04) — some terms double-count in the prose; resolved by bounding the residual instead of trusting the sum, flagged in the uncertainty list. nodes/cluster not re-probed this round — §D6.2's same-day reads cited as the live corroboration rather than re-reading (launch supplied the receipts and the round is read-only-by-evidence).
open_questions: [true 8-session peak remains class-(c) until runbook step 6 runs (this section's capture plan is the closing instrument); engine's `pinned by this process` scope taken at label value — unevictable/memory.current cross-check in the gate will confirm; whether arena/placement double-count inside pool 42.70 (affects only the split of the residual, not the verdict); `file` in memory.stat assumed ~0 under O_DIRECT — falsifier included]
next_suggested: coord folds the verdict line into the plan (D29 stands — 110 reviewed and confirmed against the receipts, no scalar change, no ladder pre-emption), adopts §R8-Q4's capture list into the runbook step-6 prose in the next doc round, and leaves the gate + ladder to the owner per the D17 receipt law.

---

## §R9 — (A) does the 8060S APU cost the R9700 real throughput, and (B) is the DEG1 enclosure's un-enabled setting our Gen3 link?

Owner round 2026-11-13/14. (A) adjudicates §D8.5's claim — "**the visible APU costs
nothing today**" — against every distinct APU→dGPU cost mechanism the community reports
for Strix Halo (AI Max+ 395) machines. (B) adjudicates the owner's "I know there was a
setting on that [DEG1] I was supposed to enable and have not" against the enclosure's
identity and our twice-reboot-surviving `8.0 GT/s x4 of 16.0` link (§D6.6/§D8.1).
Read-only; external sources fetched 2026-11-13/14 under R9-S# keys; ticket records cited
by their own keys (RQ*, §D*, [S#]). Where a mechanism is real but our rig has no
measurement, it is marked **UNVERIFIED** — this round adds none by analogy.

### R9 TL;DR (verdict-first, two lines)

**A — the claim stands as written for TODAY (zero measurable cost, three live lines
confirm it), but it is RIGHT-BUT-OVERSTATED as a general statement:** the community's
repeated "the APU costs the dGPU" is mostly about TWO specific couplings — (1) the
Strix-Halo firmware **power-limit tie** (external AMD GPU capped by the APU's BIOS
power limit) and (2) **shared-LPDDR5X bandwidth contention while the iGPU is actually
computing** — and while (1) is falsified ON OUR RIG by the engine's own print
(`power cap 300 W (default 300 W, max 300 W)`, §D8.1), (2) is a real, workload-time
channel we have never measured with a loaded router (§D8.5 falsified it only because
the router reports every model `unloaded`) — magnitude UNKNOWN for our profile,
bounded structurally at the few-percent class and to be settled by the one cheap
loaded-APU A/B in the action list; **enumeration itself costs nothing attestable**.
**B — YES, plausible and well-fitted:** the DEG1 is Minisforum's **passive** Gen4-x4
OCuLink dock (no switch, no documented retimer, **not hot-plug-capable, dock+PSU must
be powered before the host boots** — those ARE its "settings", STH + Newegg-manual
clauses quoted below), and every source that documents this symptom class on this port
class points at a **host-side link-speed decision** (EVO-X3 fix-guide: set the OCuLink
port to explicit **PCIe Gen4, not Auto**; radiance's own rig doc: a firmware slot-speed
pin "stops the slots training at a lower generation"; egpu.io: idle LnkSta readings
lie, load-state readings don't — ours was taken at 50% busy and survived reboots, so
it is real). Our failing hop is exactly ONE physical link — root port `00:03.1` (Gen4-x4
cap) ↔ the **card's own** integrated Navi switch upstream port `c2:00.0` — because
`c2/c3` are `1002:1478/1479`, the R9700's internal switch pair, NOT dock silicon
(daimonionnn capture, verbatim below): the DEG1 contains no switch to fix. Expected
payoff at Gen4 x4 from §D8.2(a)'s own model: prefill 249→~450–500 tok/s, warm decode
19.3→~35–40 t/s (compute floor caps it near 35), TTFT roughly halves; what the fix
does NOT buy is stated at B5.

### R9-A1 — Does an idle/near-idle iGPU consume measurable LPDDR5X bandwidth?

- **What is documented about the memory model (no idle tax claimed):** ROCm's official
  Strix-Halo optimization page: "On Strix Halo GPUs (gfx1151) memory access is handled
  through GPU Virtual Memory (GPUVM), which provides per-process GPU virtual address
  spaces (VMIDs) rather than a separate, discrete VRAM pool… **GTT allocations are
  dynamic and are not permanently reserved, allowing the operating system to reclaim
  memory when it is not actively used**" [R9-S1: rocm.docs.amd.com/en/docs-7.2.0/how-to/system-optimization/strixhalo.html, Memory settings, accessed 2026-11-14]. I.e. the
  APU's mapped window into the same LPDDR5X is demand-driven: idle ⇒ nothing mapped,
  nothing streaming.
- **Community measurements: none found for "idle iGPU steals bandwidth from a dGPU."**
  Searches this round (Phoronix Strix Halo platform profiles, r/LocalLLaMA, strixhalo.wiki,
  daimonionnn's two-rig notebook) surface contention numbers only where the iGPU is an
  ACTIVE compute device: jasl123 in the Framework dGPU thread: "AI Max is slower than
  M4Max… because **256 GB/s memory bandwidth would be a bottleneck**" [R9-S2:
  community.frame.work/t/request-verify-dgpu-support/69392, post #5/#6, accessed
  2026-11-14] — a statement about the iGPU doing the serving, not about its idle cost.
  daimonionnn's whole `halo-win` dataset measures the same from the other side (iGPU
  actively serving split MoE layers) [R9-S3: raw.githubusercontent.com/daimonionnn/multi-gpu-llm-toolkit/refs/heads/main/doc/benchmarks.md, accessed 2026-11-14].
  **Idle-APU bandwidth tax: UNVERIFIED — and crucially, no report claiming it exists
  was found either.** The honest statement is: no published measurement, our own
  receipt sees zero APU compute (router `/v1/models` all-`unloaded`, §D8.5-iii).
- **The display engine headless question:** no source found quantifying a headless
  RDNA3.5 display block's DRAM traffic on Strix Halo — **UNVERIFIED**. What IS on
  record: the engine prints the APU's power state honestly: `power cap unknown …
  runtime pm active (control on)` for c5:00.0 (§D8.1), and the kernel module-parameter
  docs note runtime PM is a **dGPU** mechanism ("Override for runtime power management
  control for **dGPUs**… default is -1 (auto enable)" — `runpm`, [R9-S4:
  kernel.org/doc/html/latest/gpu/amdgpu/module-parameters.html, accessed 2026-11-14]),
  so the APU does not sleep the way a parked dGPU does; but its clocks idle via DPM
  and with no queue work there is nothing to stream. No contradiction found.
- **Applies to us?** Conditionally-zero: our APU is idle whenever the router holds no
  model; the §D8 probe state was exactly that.

### R9-A2 — Does KFD/HIP enumeration of the APU cost anything?

- ROCr's env surface documents what enumeration-side knobs exist — `HSA_ENABLE_SDMA`
  ("enable or disable the use of DMA engines in all copy directions… when using the
  following APIs: hsa_memory_copy, hsa_amd_memory_fill, hsa_amd_memory_async_copy…"
  [R9-S5: rocm.docs.amd.com/projects/ROCR-Runtime/en/docs-6.1.1/environment_variables.html, accessed 2026-11-14]) — and GPUOpen shows it used for peer-copy tuning on
  multi-GPU boxes ("SDMA engines are used by default in ROCM 5.4 and below [for peer
  copies]", [R9-S6: gpuopen.com/learn/amd-lab-notes/amd-lab-notes-gpu-aware-mpi-readme/, accessed 2026-11-14]). These are **users-of-the-APU** knobs: they change how an
  app copies, and none of them taxes a dGPU when the APU is unused.
- **Memory-type wrong-pick risk (the engine reading the wrong bank):** the documented
  APU-side bugs on this class are all "app uses the APU" failures — daimonionnn's
  rocm-bugs.md matrix: "isLargeBar cap — ROCm hardcodes it off for APUs; KV cache
  spill — WDDM + starved GART at 96 GB UMA; hipMallocManaged broken — gfx1151-specific"
  — with the explicit applicability line "On `dual-linux` (discrete R9700, Linux) none
  of them should reproduce, because the preconditions do not exist: no integrated GPU,
  no BIOS UMA split…" [R9-S7: …/doc/rocm-bugs.md, accessed 2026-11-14]. Radiance pins
  `1 device(s) [0:gfx1201]` (§D8.5-ii) and allocates device-local + its own pinned host
  pool; the APU is enumerated by /sys walks but never targeted. **No cost attested.**
- **The one genuine APU+dGPU interaction bug found:** "Splitting across two AMD GPUs
  **corrupts output unless peer copies are disabled**" (halo-win, llama.cpp ROCm
  tensor-split, 8060S + R9700) [R9-S3: benchmarks.md ToC, accessed 2026-11-14]. Applies
  only to engines that split one model across both AMD devices — radiance and the
  router's Vulkan-on-APU lanes are disjoint; recorded as a DO-NOT-sPLIT marker for
  future engine choices, not a cost today.
- Interrupts: the amdgpu `msi` parameter ("To disable Message Signaled Interrupts…
  default -1 auto, enabled" [R9-S4]) shows both devices use MSI, not a shared legacy
  line; no report of shared-IRQ cost found — **UNVERIFIED-by-absence**, claimed zero.

### R9-A3 — PCIe/fabric topology: do the APU's x16 and the OCuLink x4 share a cap?

- **Live receipt (ours, engine HARDWARE prints §D8.1):** the APU chain is
  `00:08.1 16.0 GT/s x16 (max 16.0 GT/s x16) -> c5:00.0` at FULL rate while the dGPU
  chain `00:03.1` sits at `8.0 GT/s x4` — two root ports negotiating independently and
  asymmetrically, so there is no shared speed cap tying them (if there were, the APU's
  Gen4 x16 could not coexist with the dGPU's Gen3 state — and equally, the dGPU's
  failure did not drag the APU's width). Also: our dGPU's traffic never traverses the
  APU's link, and vice-versa (both are root-port-attached).
- **Lane budget, as far as the public record goes:** the EVO-X3 teardown-blog
  (closest machine-study found for this board family): "AMD lists **16 usable PCIe 4.0
  lanes** for the processor, while this machine exposes two ×4 M.2 connections and a
  ×4 OCuLink port. **The firmware and board topology decide how those endpoints are
  rooted and whether anything is shared.** Linux proves the populated path; settling
  the aggregate question will require a second drive" [R9-S8: soothill.io/blog/2026/08/03/gmktec-evo-x3-hardware-bios-nvme-baseline/, accessed 2026-11-14] — i.e.
  the 16-lane CPU-PCIe budget covers NVMe+OCuLink; the iGPU is NOT among them (it is
  the on-die 256-bit graphics fabric surfaced at `00:08.1`); aggregate sharing among
  the x4 endpoints is explicitly unresolved even for the vendor class. **Strix-Halo
  IOD block diagrams are not public: whether `00:03.1` and `00:08.1` share an
  NBIO/upstream fabric is UNVERIFIED.** What the evidence supports: even if they share
  a fabric, our observed state (x16 Gen4 idle vs x4 Gen3 under load) shows the fabric
  is not what forces the dGPU down; the forcing candidates live in the single link
  between root port and card (B2/B4).
- **Does disabling the APU change link negotiation?** No source found either way —
  **UNVERIFIED**; but this class of machine DOES have firmware that treats AMD-dGPU
  presence specially (`AMD_PBS_SETUP` knobs, next bullet), so "APU off ⇒ different
  topology behavior" is not safely assumable — another reason the action list tests A
  by LOAD, not by BIOS surgery.
- PBS topology knobs that exist on the class (daimonionnn's map of Strix Halo
  firmware): `Primary Video Adaptor` — official ASRock manual wording: "Allows you to
  select Internal/External Graphics. Default setting is [Int Graphics (IGD)].
  Configuration options: [Int Graphics (IGD)] [Ext Graphics (PEG)]" [R9-S9:
  manualowl.com ASRock B650E-PG Riptide manual p.67 (AMD PBS section), accessed
  2026-11-14; the same option byte at `AMD_PBS_SETUP+0x05` in daimonionnn's Strix
  Halo extraction R9-S10]. This is the documented firmware surface where APU/dGPU
  roles are decided on AMD client reference firmware — not a bandwidth control.

### R9-A4 — Knobs that could recover an APU-side cost WITHOUT killing the router — and their blast radii

B1/D21 law first (repo): the router's pod schedules **by the pool name**
`amd.com/gpu-8060s` (services/gpu-ai overlay, §R6-Q2/D21) and the pool name exists only
while the APU is amdgpu-bound and product-nameable in the patched table ("THE
APU-ROWS-MUST-CARRY LAW", D24). **Any route that removes the APU from amdgpu/KFD kills
the router's APU leg** — the catalog's `-strix` unified-vulkan fallback goes with it
(RQ4:508-510). Each knob against that:

| knob | what it actually does (cite) | router blast radius | verdict |
|---|---|---|---|
| `amdgpu.runpm=0` | dGPU runtime-pm override; 0 disables idle power-down [R9-S4] | none to the APU (per-kernel it is a dGPU mechanism) — but it would PIN THE R9700 awake; nothing about APU cost | not the lever |
| BIOS iGPU disable / vfio bind `1002:1586` | strips APU from host amdgpu (ticket S17 mechanism; guide's headless recommendation) | **KILLS the router's `gpu-8060s` claim (Pending-forever) + D24 ledger row + the catalog fallback** | forbidden as a measurement; owner's temporary-BIOS-window only if ever truly needed — and there is no evidence-backed need (A1/A2 found no idle/enumeration tax) |
| `amdgpu.ip_block_mask` | "Override what IP blocks are enabled on the GPU (gfx, display, video, etc.)" [R9-S4] | **module-global** — it would hit the R9700 too (its display blocks idle anyway, but gfx masking on the serving card is fatal); a per-device variant is not documented on that page | too blunt; not ship-eligible |
| `amdgpu.dc=0` (display engine off) | not listed on the fetched module-parameters page — **UNVERIFIED at this kernel/doc**; owner read `modinfo amdgpu -a` settles presence | would break the APU's display path — our router's compute lane (Vulkan on the 8060S) does not need displays… but this is an amdgpu-global behavior question, unresolved in sources | park; measure first |
| BIOS "UMA framebuffer"/Variable Graphics Memory | ROCm docs: "AMD recommends keeping the dedicated VRAM reservation in BIOS **small (for example 0.5 GB)** and increasing the shared (TTM/GTT) limit instead" [R9-S1]; ours matches: APU prints `512.00 MiB VRAM` (§D8.1) and the cmdline already carries `ttm.pages_limit=29360128` = 112 GiB (the amd-ttm page's `pages_limit` knob in PAGES, expressed identically, [R9-S1]) | zero — already at AMD's recommended shape | nothing to recover |
| `HSA_ENABLE_SDMA=0` | switches ROCr copy paths between SDMA and kernels [R9-S5,S6] | only affects ROCr-API apps (the router's ROCm-backend lanes, if any; radiance is not ROCr-copy-based — engine uses its own "dma copy lists on DMA engine 0", §D8.1) | irrelevant to A; TP2-era interest only |
| governor/clocks (APU-side) | the APU shares the SoC's amd-pstate; host-governor persistence is already on the C12 checklist (§D6.4) | none | the free swing, already scheduled |

**Rollback-safety of everything in the action list: the APU measurement is
read-only-plus-workload (no knob at all).** That is deliberate: the one knob class
that could "recover" an APU cost (disabling it) is exactly the one the router law
forbids, and no source justifies trading the router for an unmeasured idle tax.

### R9-A5 — Verdict on "the APU is not costing you anything measurable today"

**RIGHT-BUT-OVERSTATED.** Precisely:
- TRUE for today's witnessed state, with receipts (all four channels read zero): own
  root port at full Gen4 x16 while the dGPU link fails independently (A3); engine
  enumerates only gfx1201 (`1 device(s) [0:gfx1201]`, §D8.5); router `/v1/models`
  every model `unloaded` (§D8.5); UMA carve at AMD's recommended minimum (A4 row).
- The community's "yes it costs" reports resolve, on reading, into (1) the
  **power-limit tie** — "external GPU power limit… is being tied to the APU's power
  limit… limited to the APU limit you set in the BIOS" [R9-S11: strixhalo.wiki
  External_GPU guide (raw GitHub, deseven/strixhalo-homelab), AMD GPUs section,
  accessed 2026-11-14, which links the r/GMKtec EVO-X2 "120W power limit" thread and
  the Framework thread] — **falsified on OUR rig today by the engine's own print
  `power cap 300 W (default 300 W, max 300 W)`** (§D8.1; the wiki's norm for "most
  current Strix Halo boards" is ~120 W on OCuLink/M.2 AMD cards, daimonionnn's
  paraphrase [R9-S10: doc/oculink-amd-dgpu.md, accessed 2026-11-14]: "the external
  card's power limit gets tied to the APU's… capped at ~120 W regardless of the
  card") — our card is NOT capped, so whatever the class-wide bug is, this
  board+bios+DEG1 combination escapes it today; re-check the print after any BIOS
  firmware update. and (2) **DRAM-bandwidth contention while the iGPU computes**
  (jasl123's 256 GB/s framing, R9-S2) — a real shared-fabric fact, applicable to us
  only when the router actually serves on the APU.
- **Magnitude for our profile if the loaded-router case ever co-occurs:** bound it
  honestly: radiance's host-memory demand is link-bound (≤3.94 GB/s PCIe fill today,
  ≤7.88 after B's fix) plus io_uring spans; the APU serving GGUF on the 8060S is the
  workload that would compete at the LPDDR5X controller. A concurrent APU inference
  burst can at worst claim the model's share of ~230–256 GB/s [R9-S2/S3]; our PCIe
  stream is ≤3% of that even if the memory controller fully divided against us —
  but "fully divided" is not how the scheduler behaves and NO published measurement
  of radiance-vs-APU co-serving was found. **Estimate: single-digit-percent decode
  impact at router-peak, UNVERIFIED magnitude; zero at router-idle (today).**
- **The one cheapest isolating experiment (minutes, rollback-safe, read-only-first):**
  keep radiance at rest-state receipts (D8.3 fixed probe, ≥2000-token prompt, greedy,
  n=1, run twice, quote the second — §D8.3), note decode t/s; then from the router
  load ONE GGUF that fills the 8060S comfortably and stream 2–4 concurrent requests
  against it, and re-run the SAME fixed probe WHILE that traffic runs. Compare. The
  delta IS the APU's active cost for our profile, zero config touched, and rollback
  is "stop the router load". Pair it with the read-only `gpu_busy_percent` lines for
  both cards (host sysfs, §D8.4-7 style: `cat /sys/class/drm/card*/device/gpu_busy_percent`)
  before/during/after. NO BIOS iGPU-disable is justified by anything found this round.

### R9-B1 — What the DEG1 actually is

- **Identity:** MINISFORUM DEG1 eGPU dock — "Oculink Graphics Docking Station |
  PCIE4.0*4 (up to 64GT/s) | Compatible with ATX/SFX | Supports up to NVIDIA RTX 4090
  & AMD RX 7900 XTX" [R9-S12: store.minisforum.com/products/minisforum-deg1-egpu-dock,
  accessed 2026-11-14]. Newegg's spec row for the line: "Up link: Oculink 4i
  (PCIE4.0x4) Down Link: PCIEx16 (PCIE4.0x4) … Note1: OCulink interface does not
  support hot plugging, and the machine needs to be turned off" [R9-S13:
  newegg.com/p/1DN-0432-00001 product page text, accessed 2026-11-14].
- **Internal silicon:** STH's teardown-level look: "On the bottom, we have a PCB that
  handles the Oculink to PCIe slot as well as the power functions" — no bridge, retimer
  or switch mentioned anywhere in the article [R9-S14: servethehome.com/minisforum-deg1-oculink-egpu-dock-quick-look-amd-nvidia/, 2024-08-23, accessed 2026-11-14].
  So: **passive OCuLink→slot PCB + PSU wiring** is what is documented; a
  retimer/redriver presence is **UNVERIFIED** (nothing in vendor materials claims one;
  contrast morgwai's adapter-world statement that among M.2→OCuLink adapters "OCuP4V2
  is at least one category higher than F9G as it has a redriver, while F9G does not"
  [R9-S15: egpu.io thread p.3 reply, January 21 2026, accessed 2026-11-14] — redriver
  presence is a genuine tier differentiator in this connector class, and a passive path
  is more cable/length/EMI-sensitive at Gen4 rates — which matters for B4).
- **Connector generation:** OCuLink = SFF-8611-class, 4 lanes; vendor rating Gen4 x4
  (64 GT/s aggregate marketing figure, R9-S12). Gen5 is out of the dock's spec — our
  card's Gen5 capabilities (c2–c4 prints) are forward-compatible noise, not headroom.
- **Power/hotplug requirements (these ARE the dock's "settings"):** STH's operational
  sequence verbatim: "1. Turn the Oculink-capable PC off 2. Ensure power to the power
  supply and the power supply is on 3. Power on the DEG1 via the button 4. Wait a few
  seconds 5. Connect the DEG1 and Oculink capable PC using the Oculink cable… 6. Turn
  the Oculink-capable PC on. **Plugging in the Oculink cable was unsuccessful when the
  mini PC was already running**" [R9-S14].

### R9-B2 — The setting(s) a user must enable, and which fits our symptom

1. **Dock-side (DEG1 itself): power sequencing + no-hotplug** (R9-S14/S13 above). A
   dock powered on mid-session (or a host booted before the dock) risks enumeration at
   degraded or absent state. Rollback = obey the procedure. Fits partially: it would
   more plausibly cause absence (DEG1 "would not enumerate on PCIe bus" on a GMKTec M7,
   egpu.io R9-S16) than a clean Gen3 train.
2. **Host BIOS per-slot PCIe speed**: the EVO-X3 fix-page (the closest host):
   "Navigate to **Advanced → PCI Subsystem Settings** and ensure the OCuLink port is set
   to Enabled with **PCIe Gen4 selected as the link speed (not Auto, which can fall back
   to Gen1 on some docks)**" [R9-S17: tldevtech.com/fix/gmktec-evo-x3/oculink-egpu-not-detected,
   accessed 2026-11-14 — TRUST FLAG: SEO-style fix-aggregator; treat as lead, not
   authority; the AMI "PCI Subsystem Settings" page it names is stock AMI aptio, and
   GMKtec publishes no BIOS guide for the EVO-X3 ("does not yet publish an EVO-X3 BIOS
  guide", R9-S8) so no primary menu screenshot was located — the corroborating authority
   for this class is (3)]. Independently, the ENGINE's OWN rig doc puts a slot-speed pin
   on the firmware checklist for exactly the half-rate symptom: "PCIe link speed of both
   slots | **Gen5** | **stops the slots training at a lower generation**" [R9-S18:
   codeberg.org/StillDeadcode/radiance docs/PREPARING_YOUR_RIG.md §1 @v1.17.0, accessed
   2026-11-14]. **This is the best candidate for "a setting on that I was supposed to
   enable and have not" — with the correction that it lives in the HOST BIOS (the
   OCuLink port's slot speed), not on the DEG1.**
3. **Host BIOS ReBAR chain: "Above 4G Decoding | enabled | needed for Resizable BAR;
   Re-Size BAR Support | enabled; CSM disabled"** [R9-S18] — our card already runs at
   full 32 GiB BAR (engine `claimable 29.30 GiB`, §D8.1) ⇒ already enabled, not our gap.
4. **AMD PBS `Primary Video Adaptor` (IGD/PEG) and `Non-Eval Discrete GPU Support`**:
   Strix-Halo firmware DOES contain AMD-dGPU-specific paths (daimonionnn's byte map:
   `AMD_PBS_SETUP` offset `0x05` = Primary Video Adaptor, offset `0x35` = "Enable to
   support Non-Eval Discrete GPU that doesn't have specific EVAL_PWRGD(B30),
   EVAL_PRESENT#(A5)" [R9-S10: doc/oculink-amd-dgpu.md, accessed 2026-11-14]) — their
   investigation CLOSED the explanation (a working same-BIOS MS-S1 Max reads the same
   bytes with the R9700 running at **Gen4 x4 on root port `00:03.1`**) but proved the
   machinery exists and is how this firmware class treats AMD cards. We enumerate and
   serve ⇒ we are past that gate; not our setting.
5. **Cable/seat (not a setting but the sibling fix)**: the engine's own doc "An idle
   link reads 2.5 GT/s in lspci, and that is normal. If one card measures half the
   other's rate **under load**, the PCIe power state of its root port is stuck one level
   down, and **a reboot clears it**" [R9-S18 §5]. Our case: under-load read
   (`[read at 50% busy]`, §D8.1), three boots, one explicit reboot — did NOT clear.
   Per that doc's own decision tree, "stuck, reboot-clears" is falsified for us ⇒ the
   remaining candidates are the speed PIN (R9-S18 §1 table / R9-S17) or the electrical
   path (cable/seat/dock — the passive-path point of B1). The discriminator is the
   TargetSpeed read (B4).
- **Reported-symptom harvest (same family, other rigs):** the egpu.io January 2026
  thread — owner stuck "getting anything above 2.5GT/s with OCuLink dock" across
  Minisforum DEG1 (never enumerated) + ADT-F9G-BK7 + OcuP4V2 — resolved to full
  bandwidth, with the community's caution that **idle LnkSta readings show
  powersave speeds and only load reads are meaningful** ("the power savings mode
  shifting the link speed… in-game environments will push for more throughput", and the
  withdrawn dual-GPU comparison in R9-S3 was withdrawn precisely because an enclosure
  "was not negotiating USB4 v2 at all — it trained **Gen2 x4, 1.41 GiB/s measured**")
  [R9-S16: egpu.io/forums/thunderbolt-linux-setup/need-help-troubleshooting-poor-gt-s-with-oculink-dock/, accessed 2026-11-14; R9-S3]. **That is the shape of our
  situation witnessed elsewhere on this dock line: a Genx-forced-down link that only
  load-state reads reveal, and cable/dock/host triple as the variable set.**

### R9-B3 — Manual speed-override path (documented, measurable, NOT to apply blindly)

- The canonical script shape (used in AMD/TI bring-up contexts): Alex Forencich's
  `pcie_set_speed.sh` — reads `CAP_EXP+0c.L` (LnkCap), walks UP to the bridge/port if
  the target device is an endpoint (`pt` in {RCiEP/…} rule), masks in the new speed at
  `CAP_EXP+30.L` (LnkCtl2 bits [3:0] TargetSpeed), then `setpci -s $dev CAP_EXP+10.L=20:20`
  — "Triggering link retraining…" — with the stated purpose "uses setpci to change a
  device's target link speed… useful… for testing a device at a lower bandwidth"
  [R9-S19: github.com/alexforencich/verilog-pcie scripts/pcie_set_speed.sh +
  alexforencich.com/wiki/en/pcie/set-speed, accessed 2026-11-14]. A TI E2E field report
  shows the same script actually flipping link rate on live hardware ("able to change
  the PCIe link rate from 5GT/s (Gen2) to 2.5GT/s (Gen1) by using the PCIe Set Speed
  script") [R9-S20: e2e.ti.com AM6548 thread, accessed 2026-11-14].
- Risks, stated from the mechanism not folklore: the retrain bit acts on a LIVE link —
  if the GPU is mid-allocation the retrain window can error the device (the whole point
  of doing it only with radiance scaled to 0 and the router idle); a failed Gen4
  retrain falls back to the last good rate (harmless); writing TargetSpeed ABOVE both
  partners' LnkCap max is clamped by the script itself (`if speed > max_speed`). It is
  a WRITE: owner-lane, and **only diagnostic value** — if forcing TargetSpeed=4 +
  retrain lands at 16 GT/s under load, the electrical path is fine and the state was a
  firmware default; if it re-falls to 8, it is electrical (cable/dock/seat). A BIOS
  change (if the menu exists on this board) is the persistent equivalent; the kernel
  has no supported per-slot speed pin (nothing in-device-tree) — **UNVERIFIED**: no
  distro/kernel doc found claiming one.

### R9-B4 — THE TOPOLOGY READ (where negotiation fails, in which silicon)

Chain as printed: `00:03.1 8.0GT/s x4 (max 16.0GT/s x4) → c2:00.0 8.0GT/s x4 (max
32.0GT/s x16) → c3:00.0 32.0GT/s x16 → c4:00.0 32.0GT/s x16` (§D8.1). Reading:
- **c2:00.0/c3:00.0 are the CARD's own silicon, not the dock's**: "every Navi part
  presents an integrated switch pair, `1002:1478` upstream and `1002:1479` downstream,
  so `00.0-[c2]----00.0-[c3]--+-00.0 Navi 48` is a plain direct attachment, not a
  tunnel or a dock switch. A working MS-S1 Max reports the same `1002:1478` in front
  of its R9700" [R9-S10: doc/oculink-amd-dgpu.md, withdrawn-caveats section, accessed
  2026-11-14]. **Consequence for the plan: the DEG1 contributes no negotiation brain —
  exactly ONE link trains in our path (root port ↔ c2 upstream port), across the
  OCuLink cable and the passive dock PCB. c2's "max 32.0GT/s x16" is the bridge's
  advertised ceiling (the card is Gen5/x16-capable), and its `x4` width is the
  connector's physical lane count — the OCuLink x4, per the dock's own spec "Up link:
  Oculink 4i (PCIE4.0x4)" [R9-S13]. Width is by-design, exactly §D6.6's ruling;
  SPEED is the single defect.**
- **Where it fails:** one link ⇒ the candidate set is (root-port firmware speed pin —
  host BIOS; root-port equalization failure at Gen4 — electrical: cable quality/seat/
  dock PCB — recall B1's passivity point; or the endpoint side refusing Gen4 — ruled
  out by the same card+bridge pair training Gen5 x16 internally at c3/c4 and by other
  hosts reporting it at Gen4 x4: the MS-S1 witness's "R9700 over OCuLink at Gen4 x4"
  [R9-S10] and the Z890 control "the same PCIe 4.0 x4, out of the box" [R9-S10]).
- **§D6.6's discriminator survives, sharpened:** `LnkCtl2: TargetSpeed` on `00:03.1` —
  if it reads 8.0 GT/s (Gen3) ⇒ firmware PIN (fix in BIOS; tldevtech's menu, if the
  EVO-X3 has it, is the lever) — if it reads 16.0 with LnkSta at 8.0 ⇒ **electrical**:
  reseat/swap the OCuLink cable first (Gen4-rated; the community's cable-tier point
  R9-S16), then suspect the dock's passive path (try the other host port class or a
  redriver-equipped adapter — the ADT/OcuP4V2 tier — before declaring the DEG1 itself
  at fault). Owner commands (all read-only, extend §D6.6's block):
  `sudo lspci -vvv -s 00:00:03.1 | sed -n '/LnkCap:/,/LnkSta2:/p'` — LnkCtl2 TargetSpeed
  AND `LnkCtl:` ASPM/L1 state, `LnkSta2` equalization bits (the LTSSM Gen4-equalization
  completion flags live here when reported) — `sudo lspci -vvv -s 0000:c2:00.0 | sed -n
  '/LnkSta:/,/SlotSta:/p'` — the bridge side's view of the SAME link plus
  `SlotCaps/SlotSta` (hot-plug presence/attention bits if the board wires them;
  OCuLink consumer ports commonly do NOT — R9-S13/S14); `cat
  /sys/bus/pci/devices/0000:c2:00.0/current_speed current_width` for the kernel's own
  read; `sudo dmesg | grep -iE 'pcie.*(training|retrain|downgraded|equalization)'`;
  and `lspci -nn -s 0000:c2:00.0` to print the bridge VID:DID (expected `1002:1478` —
  if a DIFFERENT vendor's ID appears, a dock silicon premise changes and this section's
  reading must be redone — cheap falsifier).
- **What the width/speed split says about TP2 expectations (superseding note):**
  RQ4's "~13.4 GB/s symmetric through the PEX switch fabric" story presumes an
  external PEX88048/88096 for the SECOND card; the CURRENT dock has no switch at all
  (B1) and the in-card switch pair is a point-to-point lane-bundler, not a fan-out —
  two R9700s cannot share this DEG1's single x4 uplink; the TP2 lane plan (M.2→OCuLink
  adapters or a second dock) stands, and the switch-fabric caveat stays where it was:
  direction-corroborated, figures UNVERIFIED [RQ4:464-467].

### R9-B5 — The payoff model, from §D8's own arithmetic

Inputs (all from §D8.2(a), which is the ticket's printed-receipt model):
`all-miss decode token = 48 × 10 × 2.42 MiB = 1,162 MiB`; Gen3 x4 = 3,755 MiB/s;
Gen4 x4 = 7,510 MiB/s; observed warm miss fraction m ≈ 0.17 (at 19.3 t/s) and prefill
15.1 MiB/token (the 249 t/s receipt ⇒ the docs' 15 MB/token model class).

| quantity | now (Gen3 x4) | after fix (Gen4 x4) | basis |
|---|---|---|---|
| all-miss decode ceiling | 3.2 t/s | 6.5 t/s | 3755 or 7510 ÷ 1162 |
| warm single-stream decode (m=0.17 ⇒ 197.5 MiB/token) | 3755/197.5 ≈ 19–20 t/s — "we are there" | 7510/197.5 ≈ 38 t/s, **but the x16-class compute floor lands it ≈ 30–35 t/s** (§D8.1/docs 29.0/28.0 ms ≈ 35) | §D8.2(a) line 2 |
| prefill | 3755/15.1 ≈ 249 t/s ✓ matches receipt | ≈ 500 t/s ceiling; **the docs' measured Gen4-x4 class is 454 @55k** ([S7]/§D8.2(a) "prefill 249→~450–500") | §D8.2(a) |
| TTFT at ~2K–55K prompts | ~12 s @ 1.8–2.3K; minutes-class @55k | roughly halves again | same model |
| an independent witness of the shape | — | daimonionnn TB5-vs-OCuLink at equal lanes: "TB5 costs **what you send across it**… activations only: **2.7–3.3%**; expert weights every micro-batch: **7.9–12.8%**" [R9-S3] — a same-width link-quality delta measured on a Strix Halo; our Gen3-vs-Gen4 is a 2× CAPACITY delta, same direction | R9-S3 |

**What Gen4 does NOT fix, stated plainly:** (1) the x4 WIDTH wall — "Four lanes against
sixteen is the constraint, and no cabling change addresses it" [R9-S3: benchmarks.md,
same section]; (2) the `experts-from-host 41.52 GiB` fact itself (tiering negotiation,
profile or TP2 — §D8.5-5); (3) the single-stream compute floor ≈35 t/s (docs'
29.0/28.0 ms x16 receipts — past the link we hit THIS, not 160); (4) the ngram 4 KiB
spans / btrfs no-dioalign facts (§D6.5); (5) the governor persistence (§D6.4); (6) the
road to 140–160 t/s stays TP2-class hardware [RQ4/TP2 doc §8].

### R9 — Conflicts and UNVERIFIED (explicit list, incl. claims of MINE this round moves)

1. **My §D8.5 claim "the visible APU costs nothing today"** — SURVIVES for the witnessed
   state (its three live lines all re-verified) but is **narrowed**: it is a statement
   about an idle APU on a rig whose power-tie is provably disengaged (300 W print), not
   a general "APUs never cost dGPUs anything." The loaded-APU bandwidth channel stays
   unmeasured for our profile (UNVERIFIED magnitude; structural bound single-digit %).
   Recommended wording going forward: "**zero measurable cost at today's router-idle
   state; the only live channel is shared-DRAM contention while the router serves, and
   the action-list A/B measures it before any knob is touched.**"
2. **My §D6.6 discriminator framing ("BIOS-pin vs cable/seat")** — SURVIVES, but this
   round RETIRES the sibling advice the engine's own fix line gave ("a reboot clears
   it"): witnessed false here (three boots including a full reboot re-print the Gen3
   state at 50% busy, §D6.6 + §D8.1); the doc's own tree routes to slot-pin-or-electrical
   [R9-S18]. Also ADD a third arm the community proves: a **passive dock + marginal
   Gen4 electrical path** falls back to Gen3 cleanly (B1's redriver-tier point) — cable
   swap is a first-class candidate, not a last one.
3. **Community "APU costs YES" reports vs their own scope**: the wiki's power-tie claim
   says "most current Strix Halo boards… ~120 W" [R9-S10/S11] — our rig prints 300 W;
   the claim and our receipt CONFLICT, our receipt wins for our rig; board/BIOS
   variance (or the tie applying only under certain firmware) is unresolved — flagged,
   re-check the print after firmware updates. jasl123's 256 GB/s bottleneck framing is
   about the iGPU SERVEING, not about a dGPU next to it — a misread would inflate the
   fear; this round says so explicitly.
4. **UNVERIFIED inventory:** EVO-X3 BIOS menu names/screenshots (no GMKtec guide
   exists [R9-S8]; R9-S17 is SEO-adjacent — corroborated only by the generic rig-doc
   slot-pin pattern [R9-S18]); whether `00:03.1` and `00:08.1` share NBIO fabric
   (AMD IOD docs not public); idle-APU DRAM tax (no report exists either way);
   `amdgpu.dc=0` semantics at kernel 7.3 (not on the fetched module-parameters page —
   `modinfo` read settles); DEG1 retimer presence (absent from all vendor/press
   descriptions; treated as passive); whether hot-plug-style mid-session power states
   can LATCH a degraded negotiation across reboots (plausible via dock power state —
   NO source found; mark as folk-physics and test by the B2 procedure, not by belief).
5. **Supersedes (for coord):** (a) the engine doc's "reboot clears it" applied to OUR
   node — now falsified with receipts (§D8.1); (b) §D6.6's "(the switch upstream)"
   label on c2:00.0 — CORRECTED: it is the CARD's own `1002:1478` integrated-switch
   upstream port [R9-S10], the DEG1 has no switch (R9-B4 re-read; §D6.6's
   conclusion — width-by-design, speed-defect — is UNCHANGED); (c) RQ4's
   switch-fabric expectations for TP2 remain direction-only UNVERIFIED and are NOT
   re-opened by this round (the DEG1's passivity removes no TP2 option because TP2
   never rode the DEG1); (d) D8.5's APU verdict wording — per #1 above.

### R9 — Ranked ACTION list (cheapest/highest-yield first; each = read / change / rollback / verification print)

1. **B2 read-only localization (minutes, zero risk, settles the fix family):** owner
   runs the B4 command block (`LnkCtl2: TargetSpeed` on `00:03.1` + `lspci -nn -s
   0000:c2:00.0` + dmesg training greps + sysfs current_speed) while radiance is mid-load
   (fixed probe running — idle reads lie, R9-S16). VERIFY against: engine next boot
   HARDWARE line still prints `8.0 GT/s x4`; the lspci TargetSpeed value is the branch
   selector (8.0 ⇒ item 2; 16.0 ⇒ item 3).
2. **BIOS slot-speed pin (if item 1 read TargetSpeed 8):** BIOS → locate the OCuLink
   port/slot speed (tldevtech's AMI path: Advanced → PCI Subsystem Settings; trust
   flag noted) → explicit **Gen4** (or Auto→Gen4), Above-4G/ReBAR left as-is (already
   working). Rollback = undo the one setting. VERIFY: next boot prints
   `00:03.1 16.0 GT/s x4`, WARN `link-below-max` GONE, prefill 249→~450–500 class and
   warm decode ≥30 on the fixed probe.
3. **Electrical path (if TargetSpeed was already 16, or item 2 didn't land):** power
   FULL DOWN (host + PSU + dock, per B2 sequence), reseat cable both ends, swap to a
   different Gen4-rated OCuLink cable if available; if still Gen3: borrow/try a
   redriver-equipped adapter tier (OcuP4V2-class, R9-S15) or the DEG1 in another rig.
   Rollback = restore original cable/seat. VERIFY same prints as item 2.
4. **Last-resort diagnostic setpci (write; radiance scaled to 0 + router idle):**
   forencich-script shape — write TargetSpeed=4 on `0000:00:03.1` and retrigger
   `CAP_EXP+10.L=20:20` [R9-S19]. Value is purely diagnostic (pin-vs-electrical in one
   minute); it resets at boot anyway. Rollback = reboot. VERIFY: mid-session
   `GET /diagnostics` hardware read (§D8.5-1) + next boot's HARDWARE line.
5. **A-load measurement (settles the owner's community question, zero config):** the
   A5 A/B — fixed probe decode/prefill idle-router vs router-serving-a-GGUF-concurrently;
   reads: `gpu_busy_percent` both cards before/during/after. Rollback = stop the router
   load. VERIFY: the DELTA; single-digit % ⇒ "APU costs ~nothing even loaded" upgrades
   from witnessed-idle to measured-live; >10 % ⇒ a real co-tenancy finding that feeds
   the strata-cutover scheduling conversation (Q11 lane), not a knob to flip today.
6. **NOT-do list (recorded):** no BIOS iGPU disable / vfio bind (kills the
   `gpu-8060s` router claim, D21/B1 + D24 law); no `ip_block_mask` (module-global);
   no HSA_ENABLE_SDMA / memlock drop-in chasing anything in this round's scope
   (radiance uses neither the ROCr copy path nor the RAM tier — §D8.4-4 unchanged); no
   reseat-blind BIOS surgery while the item-1 read takes one minute to do first.

### R9 — Sources (accessed 2026-11-13/14)

| # | URL | What it is |
|---|---|---|
| R9-S1 | rocm.docs.amd.com/en/docs-7.2.0/how-to/system-optimization/strixhalo.html | Official Strix Halo optimization page: GPUVM/no-discrete-VRAM-pool, GART vs GTT ("GTT… dynamic… not permanently reserved", default ~50% RAM), `ttm/pages_limit` knob + `amd-ttm`, BIOS carve guidance ("keep… 0.5 GB"), kernel-6.18.4 KFD requirement |
| R9-S2 | community.frame.work/t/request-verify-dgpu-support/69392 | Framework Desktop dGPU thread: jasl123's "256 GB/s memory bandwidth would be a bottleneck" (iGPU-serving framing), all-AMD platform context, cited by the wiki |
| R9-S3 | raw.githubusercontent.com/daimonionnn/multi-gpu-llm-toolkit/refs/heads/main/doc/benchmarks.md + /doc/rocm-bugs.md | Same-SoC APU+dGPU rig notebook: TB5-vs-OCuLink measured pairs (3% activations / 13% weights; withdrawn Gen2-x4-latch case), "the link decides everything — width, not tunnel", dual-AMD-GPU split corruption, ROCm APU/UMA bug applicability matrix |
| R9-S4 | kernel.org/doc/html/latest/gpu/amdgpu/module-parameters.html | Authoritative param semantics: `runpm` (dGPUs only), `aspm`, `ip_block_mask` ("Each GPU is a collection of IP blocks…"), `gartsize`/`gttsize` (deprecated/test), `dpm`, `bapm`, `msi` |
| R9-S5 | rocm.docs.amd.com/projects/ROCR-Runtime/en/docs-6.1.1/environment_variables.html | `HSA_ENABLE_SDMA` documented scope (ROCr copy APIs) |
| R9-S6 | gpuopen.com/learn/amd-lab-notes/amd-lab-notes-gpu-aware-mpi-readme/ | SDMA-vs-kernel copy practice for peer copies |
| R9-S8 | soothill.io/blog/2026/08/03/gmktec-evo-x3-hardware-bios-nvme-baseline/ | EVO-X3 (the lab's machine class) Linux-visible facts: "rear OCuLink, PCIe 4.0 ×4; **not hot-pluggable**", "AMD lists 16 usable PCIe 4.0 lanes… two ×4 M.2 and a ×4 OCuLink… whether anything is shared" unresolved, "GMKtec… does not yet publish an EVO-X3 BIOS guide", 1 GiB visible VRAM vs 120 GiB GTT aperture |
| R9-S9 | manualowl.com/m/ASRock/B650E-PG-Riptide-WiFi (AMD PBS p.67) + dev.solid-run.com PBS path | Official wording for `Primary Video Adaptor` IGD/PEG default + menu location |
| R9-S10 | raw.githubusercontent.com/daimonionnn/multi-gpu-llm-toolkit/refs/heads/main/doc/oculink-amd-dgpu.md | The R9700-over-OCuLink-on-Strix-Halo firmware investigation: root port `00:03.1` Gen4 x4 WORKING witness, PBS byte map (`0x05`, `0x35` + EVAL-pin help string), **Navi integrated switch pair `1002:1478/1479` = "a plain direct attachment, not a tunnel or a dock switch"**, ~120 W cap norm, Z890 control ("the same PCIe 4.0 x4, out of the box"), Framework Desktop R9700 BAR capture, DEG1-working-but-host-unstated report |
| R9-S11 | strixhalo.wiki/Guides/External_GPU (raw: github deseven/strixhalo-homelab) | Community wiki: "external GPU power limit… tied to the APU's power limit… limited to the APU limit you set in the BIOS" + the two linked report threads; "No problems were reported with NVIDIA GPUs" |
| R9-S12 | store.minisforum.com/products/minisforum-deg1-egpu-dock | DEG1 vendor identity/spec: "PCIE4.0*4 (up to 64GT/s)", ATX/SFX, RTX4090/RX7900XTX class |
| R9-S13 | newegg.com/p/1DN-0432-00001 | DEG-line spec row: "Up link: Oculink 4i (PCIE4.0x4) Down Link: PCIEx16(PCIE4.0x4)… does not support hot plugging, machine needs to be turned off" |
| R9-S14 | servethehome.com/minisforum-deg1-oculink-egpu-dock-quick-look-amd-nvidia/ (2024-08-23) | STH physical inspection: "native PCIe Gen4", "a PCB that handles the Oculink to PCIe slot as well as the power functions" (no switch/retimer), the 6-step power procedure, "Plugging in… unsuccessful when the mini PC was already running", HBA-doesn't-work caveat |
| R9-S15/R9-S16 | egpu.io/forums/thunderbolt-linux-setup/need-help-troubleshooting-poor-gt-s-with-oculink-dock/ (Jan 2026) | The same-symptom Linux thread: DEG1 "would not enumerate on PCIe bus" on GMKTec M7; idle vs load LnkSta lesson ("power savings mode shifting the link speed… in-game… push for more throughput"); redriver-vs-passive tier statement (OcuP4V2 vs F9G) |
| R9-S17 | tldevtech.com/fix/gmktec-evo-x3/oculink-egpu-not-detected | EVO-X3 claim: "Advanced → PCI Subsystem Settings… OCuLink port… **PCIe Gen4 selected as the link speed (not Auto, which can fall back to Gen1)**" — TRUST-FLAGGED (SEO page; no primary menu corroboration, R9-S8 gap) |
| R9-S18 | codeberg.org/StillDeadcode/radiance PREPARING_YOUR_RIG.md @v1.17.0 (fetched this round; = ticket [S3]) | The engine's own rig doc firmware table ("PCIe link speed of both slots \| Gen5 \| **stops the slots training at a lower generation**"; Above-4G/ReBAR/CSM rows), §5 idle-link normality + reboot-clears clause (ours: falsified), §6 power/undervolt context |
| R9-S19 | alexforencich.com/wiki/en/pcie/set-speed + github.com/alexforencich/verilog-pcie/blob/master/scripts/pcie_set_speed.sh | Exact setpci command shape: `CAP_EXP+30.L` TargetSpeed write + `CAP_EXP+10.L=20:20` retrain trigger + endpoint→port walk logic + stated purpose |
| R9-S20 | e2e.ti.com AM6548 "How to change the PCIe link rate" thread | Field demonstration of pcie_set_speed.sh flipping live link rate |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R9 appended)]
commands_run: [repo reads (RESEARCH RQ1/RQ3/RQ4/RQ5/Serving-envelope/§R6/§R7/§R8 + TLDR/Sources; EXPLORE §D2.8-pointer, §D6, §D8 full; DECISIONS D21/D24 blocks; runbook/TP2 greps for DEG1/board identity — none present, recorded) => pass; searxng searches ×13 (DEG1 identity/spec/settings, Gen3-downgrade threads, Strix Halo iGPU/dGPU contention, PBS, setpci, runpm, HSA_ENABLE_SDMA, EVO-X3 BIOS) => pass; web_url_read: egpu.io thread ×3 pages, strixhalo.wiki raw md, daimonionnn oculink-amd-dgpu/benchmarks/rocm-bugs/systems raws, rocm.docs strixhalo + ROCR env-vars, kernel.org module-parameters, servethehome DEG1, minisforum store, soothill EVO-X3, forencich script raw, Framework thread; webfetch of the proxy-cached copies failed twice (403) — switched to the sanctioned mcp fetch => pass; codeberg raw PREPARING_YOUR_RIG.md @v1.17.0 => pass; arithmetic re-runs of the §D8.2(a) model (Gen3/Gen4 ceilings, m-fits, prefill) => pass; reddit thread fetch NOT attempted (wiki carries the citation; noted) => consistent with plan]
deviations: none beyond scope — read-only, only RESEARCH.md written. Two launch framings answered beyond their letter because the evidence moved: (1) the brief's guess that c2:00.0 might be the DEG1's silicon is resolved the other way — daimonionnn's verbatim capture proves c2/c3 are the R9700's own integrated switch pair, so the DEG1 is passive and exactly one link negotiates; (2) the brief's "port9 vs port2" style A3 question (fabric sharing) is left UNVERIFIED by design — AMD IOD docs are not public, and the live asymmetric link states bound what such a cap could do.
friction: reddit's 120W thread unreachable via sanctioned tools (wiki carries its gist + URL — cited via the wiki, marked accordingly); tldevtech EVO-X3 menu claim has no primary corroboration (GMKtec publishes no EVO-X3 BIOS guide, R9-S8) — used as a lead with an explicit trust flag; superuser fetch bot-blocked (403) — replaced by the forencich original, which is the better source anyway; codeberg raw path form took one retry (api/v1 path).
open_questions: [does a loaded 8060S measurably cost radiance decode on this box (the action-list item-5 A/B settles it; structural bound says single-digit % — UNVERIFIED magnitude)? does the EVO-X3 BIOS actually expose a per-slot Gen4 pin (the item-1 LnkCtl2 TargetSpeed read discriminates whether a pin or the electrical path is our cause)? is the Strix-Halo power-tie board/firmware-specific (our 300 W print escapes the community's ~120 W norm — re-read after any BIOS update)? idle-APU DRAM tax — no source exists either way; treated as zero, honestly labeled UNVERIFIED]
next_suggested: coord hand the owner the R9 action list 1→2/3→5 (the link read first — one minute, decides BIOS-vs-cable; the APU A/B second — answers their community question with our own numbers), fold the supersede lines (§D8.5 wording, §D6.6 c2 identity + reboot-clears retirement, R9-S18 slot-pin as the rig-doc's own next candidate) into the next DECISIONS round, and record that NO chart change and NO knob from A4 ships — the evidence says the fix is host-side and the measurement is workload-side.

---

## §R10 — the DEG1's power-sequence requirement, and the settings that make an OCuLink eGPU train Gen3 instead of Gen4

Owner round 2026-11-14, post-D34. Authorities re-read first: §R9 (DEG1 = passive
Gen4-x4 dock; c2/c3 = the card's own `1002:1478/1479` Navi switch pair; the ONE
negotiating link is `00:03.1 ↔ c2:00.0`), §D8 (link-bound rate model), **D34 (the
owner's fresh `LnkCtl2: Target Link Speed: 16GT/s` read CLOSED the BIOS-pin arm —
config-instructed-Gen4, falling-back-to-Gen3 ⇒ signal-integrity/LTSSM territory;
suspects ordered power-sequence → cable → host-port EQ)**. This round tests that
ordering against the external record and prices the fix ladder. New citations
R10-S#; access dates 2026-11-14.

### R10 VERDICT (first)

**Highest-probability single action: the dock-first FULL-COLD-BOOT sequence —
DEG1 power button on, card fully powered, ~5 s, THEN host power — executed as a
0 %-to-break one-variable-per-cold-boot ladder with the cable reseat/swap, because
every documented DEG1-owning source says the dock's link enumeration is
gated on that exact ordering (chimolog: "make sure you power on the external GPU
first… wait about 5 seconds" — and the first-time-only recognition "ritual"; STH:
plugging while the host runs "was unsuccessful"; Newegg manual row: "does not
support hot plugging, and the machine needs to be turned off"), and because the
same dock + same GPU family on the same GPP-port number has a documented,
power-state-driven failure mode on Linux** [R10-S2,S3,S4,S6]. **The
ASPM-off/`runpm=0` class is DEMOTED as a speed fix by direct evidence** (a
live bug report shows `pcie_aspm=off` "no change to PCIe link speed" and a
runtime `setpci` retrain "no effect" when a link has EQ-failed and parked low
[R10-S5]) — but `amdgpu.runpm=0` + no-D3cold on the chain is UPGRADED to a
necessary *stability* lane for this exact rig class: the GPD+DEG1+RX 9070 XT
investigation proved root-port D3cold cuts the whole OCuLink chain ("device lost
from bus") on the SAME `00:03.1 (GPP9)` port number, fixed locally by a udev
`d3cold_allowed=0` rule [R10-S6]. If power-sequence + cable + bypass all fail to
produce Gen4, the honest read is a channel-quality failure on the passive path —
cable-brand swap, redriver-class dock (AG02/OcuP4V2 tier), or the TP2 §2
PEX-switch plan are the remaining roads; nothing chart- or kernel-side changes
that (Q5).

### R10-Q1 — The DEG1's own power requirements (vendor + hands-on record)

- **Power architecture:** ATX/SFX PSU IN the dock (24-pin to the board; the PSU also
  feeds the GPU's 8-pin(s)) — "Support ATX/SFX Standard Power Supplies" [R10-S3:
  newegg.com/p/1DN-0432-00001 DEG1 listing, accessed 2026-11-14; store.minisforum.com
  product page R9-S12]; STH: the bottom "PCB that handles the Oculink to PCIe slot as
  well as the power functions", "24-pin ATX power input", GPU retention bracket bolts
  to the PSU, "850W… 500W is likely more than enough" for the big cards [R10-S4:
  servethehome.com/minisforum-deg1-oculink-egpu-dock-quick-look-amd-nvidia/,
  2024-08-23, accessed 2026-11-14]. **No DC barrel, no host sideband power**: the OCuLink
  4i cable carries signal + PRSNT sideband only; per the egpu.io hub, the *only* known
  risers that power the eGPU from the host's extra pins are OneDock/OSU designs
  ("the only currently known riser… that has extra pins to allow the laptop to power on
  the eGPU or off" — and that family has a physical SWITCH, not the DEG1) [R10-S2:
  egpu.io/forums/custom-egpu-chassis/oculink-what-it-is-why-you-need-it-and-where-to-get-it/
  (slothman sticky, updated through 2026), accessed 2026-11-14]. **A 300 W R9700 is a
  non-issue for the dock itself** — any sane ATX/SFX covers card+slot; the slot's own
  75 W budget rides the dock PCB. The exact SFF-8611 pin-level perst/signal-power map
  = **UNVERIFIED** (VITA spec paywalled).
- **Physical switch:** YES — a side-mounted FORCE-power button with LED [R10-S3],
  the one the reviews call the dock's "power button" [R10-S4]. No jumpers/DIPs or
  firmware are documented anywhere fetched (manual PDFs are gated;
  manuals.plus/asin/B0DCZLPWXK 403'd this round — the retail manual's verbatim
  wording is therefore represented by the Newegg transcription row [R10-S3] + the
  STH/chimolog procedures below; a vendor PDF quote stays **UNVERIFIED**).
- **The documented boot sequence, three independent sources, in agreement:**
  - STH (R9-S14 = same article): "1. Turn the Oculink-capable PC off 2. Ensure power
    to the power supply and the power supply is on 3. Power on the DEG1 via the
    button 4. Wait a few seconds 5. Connect the DEG1 and Oculink capable PC using
    the Oculink cable… 6. Turn the Oculink-capable PC on. **Plugging in the Oculink
    cable was unsuccessful when the mini PC was already running**" [R10-S4].
  - chimolog (JP DEG1 review, 2025-04-21): "The power-on order is a little tricky…
    **always power on the external GPU first** — wait a few seconds and then power
    on the mini PC… A 'ritual' required only on the FIRST boot — once the GPU is
    recognized it follows reboots and power-offs" — plus the install warning "if the
    [ATX 24-pin] insertion is shallow it easily causes malfunction" [R10-S5-note →
    R10-S7 below for id; verbatim JP at chimolog.co/minisforum-deg1/].
  - Retail manual transcription: "Note1: OCulink interface **does not support hot
    plugging, and the machine needs to be turned off**" [R10-S3].
- **Cold-boot vs reboot asymmetry (owner-relevant):** the "first-boot ritual" +
  no-hotplug + the STH failure say the SAFE experiment is a **full cold boot**
  (dock button + PSU flip, host off, sequence per above), not a warm reboot — our
  three "reboot did not fix it" boots were warm rolls/restarts and the 15:01
  REBOOT ran with whatever dock power state preceded it (§D4/§D6.6/§D8.1). Whether a
  degraded training **latches across warm reboots** is not documented —
  **UNVERIFIED** (plausible mechanism: PERST#/refclk presence at the moment the
  root port runs its LTSSM; no source to claim either way beyond the ritual
  wording).
- **Does the DEG1 measure up?** chimolog's 3DMark PCIe Feature test on a
  GPD-class host: "average 7.07 GB/s (theoretical: 8.0 GB/s)" — an independent,
  hands-on confirmation that the DEG1 trains Gen4 x4 and delivers ~88% of line rate
  when the path cooperates [R10-S8: chimolog.co/minisforum-deg1/ PCIe-bandwidth
  section, accessed 2026-11-14]. **The dock is not spec'd or empirically Gen3 —
  our Gen3 is a path failure, not the product's ceiling.**

### R10-Q2 — Why an OCuLink link settles at Gen3 while asking Gen4: causes, ranked against OUR data (TargetSpeed=16GT/s, -6dB default preset, Phase1-only EQ bits, reboot-surviving, under-load reads)

| rank | cause | external evidence | fits OUR rig? |
|---|---|---|---|
| 1 | **(a) power-state/ordering latch** — link trained while dock/card not fully powered or before the chain settled ⇒ degraded training persists | the vendor/press boot-ritual trio (Q1); the GPD/DEG1 case where the SAME `00:03.1` GPP9 root port's D3cold cut the chain and lost the device until pinned off [R10-S6] | **STRONGEST** — our setup has never demonstrably executed the ritual cold-boot (owner's memory "setting I was supposed to enable" plausibly = exactly this; no cold-boot-with-dock-first witnessed in the ticket's boot history) |
| 2 | **(d) cable/connector integrity** — seating, latch not clicked, kinked/marginal SFF-8611; the tier differences are real (redriver vs plain) | egpu.io hub: "stick to the sf-8611 cable… make sure it's PCIe 4.0 compatible"; "cable length doesn't matter much for degradation **until 1.5m**"; the 2-lane-vs-4-lane SKU-lottery report (GREEN vs RED LED variants) [R10-S2]; STH's "Words of Caution" + the DEG1-enumeration-failure case on another host [R10-S4/R9-S16]; chimolog's shallow-24-pin warning [R10-S7] | **STRONG** — passive path (R9-B1) has zero silicon to compensate loss; one reseat + one known-Good-cable swap is minutes |
| 3 | **(c) Gen4 equalization fails on a marginal channel and the link parks at Gen3** — the *mechanism* behind (a)/(d): 16 GT/s EQ phases incomplete ⇒ stay at last-good speed | the live analogue, NVIDIA's RTX-5070-Gen1 case, states the failure grammar verbatim: "the driver writes 32GT/s to LnkCtl2, **Gen 5 equalization fails (`Phy32Sta: EquComplete-`), and the link falls back** to Gen 1 instead of Gen 4" [R10-S9: discourse.ubuntu.com RTX 5070 thread, accessed 2026-11-14; plus the LTSSM Recovery.Equlization phase-bit sequence in R10-S10: blog.csdn.net LTSSM article (zh), accessed 2026-11-14] | **TRUE as mechanism** — our `-6dB de-emphasis / 0dB preshoot` is the compliance DEFAULT preset, not a channel-trained one; but a standalone "host EQ bug" is only distinguishable from (a)/(d) AFTER they're cleared (that's what the ladder in Q5 is for) |
| 4 | **(e) host port/firmware** — per-slot speed pin, platform EQ settings, BIOS rev regressions | **Half-closed by the owner's own read**: `Target Link Speed: 16GT/s` ⇒ no Gen3 pin (D34); the surviving sub-cause = platform EQ presets/DTLSM tuning (the rig docs' "stops the slots training at a lower generation" pin exists *because* boards train low [R9-S18]); EVO-X3-class per-slot "Gen4 not Auto" claim is the SEO-flagged lead [R9-S17] | **WEAK-but-alive** — an explicit Gen4 (not Auto) slot setting, if the menu exists, still changes platform-side behavior worth one cold boot; the *pin* itself is ruled out |
| 5 | **(b) ASPM L1/L1.2 + runtime PM on a passive long channel** — L1 exit retrains; a marginal channel can re-fail Gen4 EQ and settle low | mechanism plausible but the evidence says ASPM does NOT fix or cause *trained* speed in the parked cases: "pcie_aspm=off kernel parameter — in place, **no change to PCIe link speed**" [R10-S9]; ASPM L0s/L1 idle states are power, not width/speed, per the amdgpu/L1 substate semantics; our LnkCap advertises "ASPM L0s L1" (normal) and the runtime state prints "(control auto)" | **NOT a cause of our Gen3 settle — BUT a real degradation/instability channel on this exact rig class** ([R10-S6]'s D3cold/BOCO/BACO chain is the same family, and it's why Q3 reads `d3cold_allowed`) |
| 6 | **(f) the card** — R9700/RDNA4 refusing Gen4 on OCuLink | counter-evidence is concrete: RX 9070 XT + DEG1 runs Gen4 x4 on a GPD host (its bugs are power-state crashes, no speed complaint) [R10-S6]; R9700 over OCuLink at Gen4 x4 on the working MS-S1 Max, same `00:03.1` root port [R9-S10]; same R9700 + DEG2 + RIITOP adapter at 4.0 x4 on an Intel Z890 [R9-S10]; RX 9070 works direct M.2→OCuLink [R10-S11: makeuseof.com/i-tested-my-egpu-with-oculink-and-thunderbolt-and-it-wasnt-close/, accessed 2026-11-14]. The engine's `pcie 0: 2.5GT/s x4 250Mhz | 1: 16.0GT/s x4 …` lines are the card's **DPM table entries** (supported states incl. 16GT), not a lane claim — and `mclk/sclk` reads are memory/graphics clocks, per the brief's don't-conflate rule: agreed, they stay out of the link argument (§D8.1) | **RULED OUT absent evidence** — no report of this card class training Gen3 on OCuLink was found anywhere this round |

Also from [R10-S6]'s cause-B writeup, a caution that APPLIES to our stability, not
our speed: on this firmware family the root port's own PM (`d3cold_allowed=1`
default, no `_PR3` resource, `SltCap: HotPlug- Surprise-`) can drop the whole chain —
"OCuLink does not support Surprise Removal… If bus loss happens during an active
session… recovery fails" — so any *experiment* here must avoid letting idle PM churn
mid-measurement (Q3/Q4 handle it).

### R10-Q3 — The read-only discriminator table (exact commands → meaning)

Owner-lane, all reads (the two writes are flagged). Rule from the record: **read
under load** — "An idle link reads 2.5 GT/s in lspci, and that is normal"
[R9-S18]; "power savings mode shifting the link speed… in-game environments push
for more throughput" [R9-S16]; the NVIDIA case proves idle-vs-load confusion is the
#1 false-negative here [R10-S9]. Have the fixed probe (§D8.3) or `stress`-class
inference running; radiance down for the writes.

| command (read) | decode |
|---|---|
| `sudo lspci -vvv -s 00:00:03.1 \| sed -n '/LnkCap:/,/LnkSta2:/p'` | `LnkSta: Speed 8GT/s (downgraded)` = the defect; `LnkCtl2: Target Link Speed: 16GT/s` (already read, D34) ⇒ **config arm CLOSED**; `ASPM L0s L1` in LnkSta means the idle-state machinery is live (stability lane, not speed); `Transmit Margin/Compliance preset -6dB/0dB` = default preset, NOT a channel-trained one ⇒ no evidence the host ever finished 16 GT/s EQ |
| `sudo lspci -vvv -s 00:00:03.1 \| grep -A1 'LnkSta2'` + `sudo lspci -vvv -s 0000:c2:00.0 \| sed -n '/LnkCap:/,/SltCtl:/p'` | bridge-side view of the SAME link (`(downgraded)` expected twice); `SltCap: HotPlug- Surprise-` ⇒ no latch/hotplug semantics on the port (also means power-cycle discipline is ALL there is); per-lspci LnkSta2/EQ bit spellings vary by version — capture verbatim, don't paraphrase (exact bit-name → phase mapping left **UNVERIFIED** on this toolchain) |
| `cat /sys/bus/pci/devices/0000:00:03.1/current_link_speed /sys/bus/pci/devices/0000:00:03.1/d3cold_allowed /sys/bus/pci/devices/0000:00:03.1/power/control` (+ same trio on `0000:c2:00.0`, `c3:00.0`, `c4:00.0`) | `current_link_speed` = kernel's own read (cross-check lspci); `d3cold_allowed 1` + `power/control auto` on the ROOT PORT = the [R10-S6] bus-loss precondition is armed on our box too ⇒ pinning those is Q4's *stability* row even if it changes no speed |
| `cat /sys/module/pcie_aspm/parameters/policy` | `[default] powersupersave/performance` — documents the policy state; per [R10-S9] do NOT expect a speed change from toggling it |
| `sudo dmesg \| grep -iE 'pcieport 0000:00:03.1|link (training|downgraded|retrain)|LTSSM|Gen[0-9]|equaliz'` | the kernel logs `link training` events + `PCI: Bridge: to [bus …]` re-enumerations on the port at boot; repeated retrain/fallback lines around boot = LTSSM struggling (absence = silent first-attempt Gen3) |
| `sudo journalctl -k -b \| grep -i 'available PCIe bandwidth'` | the boot line D34 records (`31.504 Gb/s … limited by 8.0 GT/s x4 … capable of 504 Gb/s`) — one per boot, timestamps WHICH boots were degraded (count vs "three boots" — did ANY boot run dock-first-cold?) |
| engine's own `link` line + `GET /diagnostics` under load (§D8.5-1) | the load-state witness we already trust: `8.0 GT/s x4 [read at 50% busy]` |
| **dynamic debug**: `echo 'file drivers/pci/* +p' > /sys/kernel/debug/dynamic_debug/control` | **that is a WRITE to kernel state** (changes dmesg verbosity; harmless-ish, non-persistent) — owner-decided only if the dmesg grep above is mute; not a repo proposal |
| **THE physical discriminator (Q5 step 4): bypass the dock** — card+cable into the host's own OCuLink port with NO dock (open-frame), or DEG1+card into a second Gen4 host (the Z890-control move [R9-S10]) | Gen4 there with the SAME cable ⇒ the dock's PCB/power path is the defect; Gen3 still ⇒ the host port ↔ cable ↔ card triple owns it, and the cable swap (Q5 step 3) is what separates the last two |

### R10-Q4 — Candidate fixes, cheap → expensive, risk, verification print

Verification print for ALL rows (unchanged from §D8.2/R9-B5): boot-time `journalctl`
bandwidth line + `LnkSta` under load + the engine's `link … [read at NN% busy]`
hard-asserts `16.0 GT/s x4`; rates must then move prefill 249→~450–500 tok/s and warm
decode toward the ~35 t/s compute floor. Anything that doesn't land `LnkSta` first is
not a fix, it's hygiene.

| $ | change | precision note | risk | rollback |
|---|---|---|---|---|
| 0 | **Cold-boot ritual ×2-3** (PSU flip, dock button, ≥5 s, host on; never the cable while hot) | the vendor/press-documented enumeration gate (Q1); zero hardware change; the one-variable law D28(5) applies | ~0 | undo = boot normally |
| 0 | **Reseat** OCuLink both ends "until the latch clicks"; full 24-pin; fresh AC cord seating [R10-S7 warns shallow = malfunction] | same family as ritual | ~0 | — |
| 1 | **Cable swap** to a different known-Gen4 SFF-8611 cable (short; the hub says quality>length until ~1.5 m) [R10-S2] | cheap, decisive vs cause (d) | ~0 | swap back |
| 1 | **BIOS: per-slot explicit Gen4 (not Auto)** + re-check Above-4G/ReBAR unchanged; ONLY if the menu exists on this board (EVO-X3-class: [R9-S17] trust-flagged; no GMKtec BIOS guide published [R9-S8]) | TargetSpeed=16 says no *pin*, but a platform EQ path can still differ per BIOS rev — plausible, low-confidence | one wrong slot setting; screenshot before/after | undo setting + cold boot |
| 2 | **Stability hygiene (NOT a speed fix):** udev `d3cold_allowed=0` on the 5-chain devices incl. root port + `amdgpu.runpm=0` (the [R10-S6] workaround verbatim; runpm semantics: [R9-S4]) | prevents mid-session link-off events on this rig class; ASPM-off explicitly does NOT move a parked speed [R10-S9] — keep `policy` default; `runpm=0` costs the card's idle power draw only | kargs/udev, reboot | remove rule/param |
| 2 | **Forced retrain** `setpci … CAP_EXP+10.L=20:20` (Retrain bit; forencich shape [R9-S19]) | diagnostic-only: a healthy LTSSM re-attempts 16 EQ ⇒ if the channel is marginal the retrain either lands (then a cold boot should too — proves latch) or no-ops exactly like [R10-S9]'s field case | link blip mid-I/O = driver errors ⇒ radiance scaled to 0 | already re-executed at next boot; no persistence |
| 3 | **TargetSpeed re-write + retrain** (`setpci CAP_EXP+30.L` per [R9-S19]) | our value ALREADY reads 16GT/s ⇒ this row collapses into the forced-retrain above unless a BIOS rev or the NVIDIA-style "driver writes a WRONG target (32)" case applies — no wrong target here | same as row 2 + "link-down/unbootable" lore [D34] | owner power-cycle |
| 4 | **Bypass/replace the dock** (open-frame direct, or redriver-tier AG02/OcuP4V2 [R9-S15], or the DEG1-in-another-host control) | the definitive separator (Q3) | labor; open frame = physical care | — |
| 5 | **PEX Gen4 switch** (the TP2 §2 family — ASM2824/PEX88048-class as the ticket's RQ4 already contemplates) between host and dock | re-establishes equalization authority & shortens each passive segment; this is ALSO the TP2 second-card lane, so it's spend the plan already contemplates — but buy only if rows 0-4 prove "passive path cannot hold Gen4 here" | capital; switch adds latency (~1-2 µs class — **UNVERIFIED** magnitude) | keep for TP2 regardless |
| — | **NOT fixes** (recorded so they don't get retried): `pcie_aspm=off` for speed [R10-S9]; `setpci` retrain as a *cure* [R10-S9]; HSA/amdgpu knobs (R9-A4); software touching the card's own `mclk/sclk` or the ngram tier — none is the link | | | |

### R10-Q5 — Verdict + ordered ladder (one variable per cold boot)

**Ladder:** (1) ritual cold boot ×2-3 exactly per Q1 → read `LnkSta`; (2) reseat
cable both ends + 24-pin → read; (3) swap cable → read; (4) **bypass the dock**
(card on the host's OCuLink port open-frame, or the DEG1+card on a second Gen4
host) → read; (5) BIOS slot-pin IF the menu exists → read; (6) whatever the winner
was, make it permanent, then add the row-2 hygiene (`d3cold_allowed=0` chain rule —
stability, not speed); (7) only if steps 1-5 all print 8GT/s: the passive channel
cannot hold Gen4 in this chassis — the switch/redriver-dock purchase decision
(TP2 §2's lane) is next, and until then **the ceiling stays 3.94 GB/s and the only
rate levers are the §D8 profile ones** (pool/ctx/seqs negotiation or TP2-class
hardware — nothing else is honest).
**Probability read (stated as judgment, labeled):** highest single-action
probability is step 1-3 collectively (ordering/latch + cable, causes (a)/(d)) —
the vendor record makes the dock's enumeration order-gated, our boot history never
witnessed the ritual, and the chimolog 7.07 GB/s witness says the dock itself
trains Gen4 when respected [R10-S8]. Step 4 is the *definitive* one. Step 6 is
near-certain no-op for speed by direct evidence [R10-S9].
**Prove-it-worked:** `LnkSta: Speed 16GT/s x4 (no downgraded)` under load + boot
line `…limited by 16.0 GT/s PCIe x4` gone + engine HARDWARE `link 00:03.1 16.0
GT/s x4` + fixed-probe prefill ≈450–500 / warm decode climbing 19.3 → 30-40 band,
landing near ~35 (compute floor, §D8.2). If prefill lands ~500 but decode doesn't
move, re-read the m-value before celebrating (the §D8 model separates the legs).

### R10 — Conflicts / SUPERSEDES / UNVERIFIED

- **Supersedes §R9-B2's ordering emphasis on the BIOS-pin arm:** D34 (owner read) +
  this round confirm: the `Target Link Speed` is already 16 — the pin candidate is
  CLOSED except as an EQ-path BIOS-rev quirk; §R9's action-list item 2 ("if
  TargetSpeed reads 8") is now moot-but-unharmful; the surviving discriminator is
  the dock-bypass (Q5-4), not the `LnkCtl2` read.
- **Supersedes any ASPM-hope reading of §R9's item list** (it wasn't there — recorded
  so it doesn't enter the tuning note's next fold): ASPM-off is NOT a
  link-speed fix [R10-S9]; it (and runpm pinning) belong in the tuning note as
  **stability** items for exactly this dock+RDNA4+GPP-port chain [R10-S6].
- **§D8/§R9 numbers untouched**: passivity of the DEG1, the c2/c3 card-bridge
  identity, and the payoff model all re-confirmed by independent witnesses
  ([R10-S6] names the same `1002:1478/1479` chain; [R10-S8] the Gen4 ceiling).
- **UNVERIFIED (explicit):** DEG1 official PDF manual text (fetch 403; retail row +
  two reviews carry the same content); SFF-8611 per-pin perst/signal-power map;
  whether a degraded training latches across warm reboots on this chipset (the
  ritual wording implies first-contact matters; no spec citation); lspci LnkSta2
  bit-name↔phase mapping on this toolchain; EVO-X3/our-board BIOS menu existence;
  switch-latency magnitude for a PEX Gen4; the -6dB preset's host/card-side
  attribution (which end owns the un-trained preset — spec-adjacent, not sourced).
  Chimolog's host is a different mini-PC (EVO-X1/HX370) — transferable as dock
  evidence only, board claims are its own.

### R10 — Sources (accessed 2026-11-14)

| # | URL | What it is |
|---|---|---|
| R10-S2 | egpu.io/forums/custom-egpu-chassis/oculink-what-it-is-why-you-need-it-and-where-to-get-it/ (slothman sticky + updates) | OCuLink doctrine: SFF-8611 cable guidance ("stick to that cable… PCIe 4.0 compatible"), length→1.5 m, SKU lottery (2-lane GREEN vs 4-lane RED variants; cuda-z/aida64 proof rule), extra-pin power-on risers exist ONLY on OneDock/OSU (not DEG1), GPD-G1 80/100/120 W BIOS-flash power caps (APU-side TDP tying an external AMD card — the class of coupling our 300 W print escapes) |
| R10-S3 | newegg.com/p/1DN-0432-00001 | DEG1 retail spec row: ATX/SFX, "Up link: Oculink 4i (PCIE4.0x4) Down Link: PCIEx16(PCIE4.0x4)", "does not support hot plugging, and the machine needs to be turned off", power-button description |
| R10-S4 | servethehome.com/minisforum-deg1-oculink-egpu-dock-quick-look-amd-nvidia/ (2024-08-23) | Passive PCB ("handles the Oculink to PCIe slot as well as the power functions"), 24-pin input, PSU sizing, the 6-step cold-boot procedure, "unsuccessful when the mini PC was already running", HBA-doesn't-work caveat |
| R10-S7 | chimolog.co/minisforum-deg1/ (2025-04-21, JP) | DEG1 assembly + the power ORDER verbatim ("外付けグラボから電源を入れて…5秒くらい待って…ミニPCの電源" — dock first, ~5 s, then host; first-boot "ritual" then it follows reboots; shallow-24-pin malfunction warning) |
| R10-S8 | same page, PCIe link-speed section | 3DMark PCIe Feature Test on DEG1: avg **7.07 GB/s** (theoretical 8.0) — third-party proof the dock trains Gen4 x4 |
| R10-S9 | discourse.ubuntu.com/t/rtx-5070-pcie-link-speed-stuck-at-gen-1…/77366 | Live "asks Gen5, EQ fails (`Phy32Sta: EquComplete-`), falls back below target" bug grammar; `pcie_aspm=off` = no speed change; runtime `setpci` retrain = no effect; BIOS speed-lock overridden by driver; upstream NVIDIA issue 1010 |
| R10-S10 | blog.csdn.net/weixin_45176819/article/details/134032000 (zh) | LTSSM Recovery.Equlization phase-bit register walk (16.0 GT/s Phase1/2/3 + Complete bits) — secondary, used only for the phase-sequence grammar |
| R10-S6 | github.com/ArcheoCodix/egpu-oculink-fix (README + docs/topo.md + issues/B-d3cold-bus-loss/) | **GPD Win 4 + DEG1 + RX 9070 XT (Navi 48) on Linux**: same GPP `00:03.1` root port + same `1002:1478/1479` card-side switch chain; root-port D3cold ⇒ "device lost from bus" ⇒ udev `d3cold_allowed=0` resolved; Mario's B3/B2 patches partial (BACO path still drops); `SltCap HotPlug- Surprise-`; ATPX/`_PR3` absence; DS_GFXCLK wake + MES fw causes (stability family, not speed) |
| R10-S11 | makeuseof.com/i-tested-my-egpu-with-oculink-and-thunderbolt-and-it-wasnt-close/ | RX 9070 on direct M.2→OCuLink vs TB3 — card-class works on the path (no Gen3 complaint) |
| (inherited) | R9-S4 kernel amdgpu module-parameters; R9-S10 daimonionnn MS-S1/Z890 witnesses; R9-S15/S16 egpu.io thread (redriver tier, idle-LnkSta lesson, DEG1-enumeration-failure report); R9-S17 EVO-X3 BIOS lead (trust-flagged); R9-S18 radiance PREPARING_YOUR_RIG §1/§5 (slot-speed pin row; idle-link normality; reboot-clears, ours falsified); R9-S19 forencich setpci shapes; R6-S14 | carried per §R9; nothing re-fetched contradicted them |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R10 appended)]
commands_run: [repo reads: DECISIONS D30-D34 block verbatim (D34's LnkCtl2 ruling + isolation ladder = the premise), §R9/§D8/§D6.6 re-read => pass; global-searxng web_search x6 (DEG1 manual, GMKtec Gen3 reports, RX9070/R9700 Gen3 reports, cold-boot lore, EQ fallback, loss budget) => pass; web_url_read: egpu.io OCuLink hub x2 pages, chimolog DEG1 x2 (procedure + 3DMark bw), Ubuntu RTX-5070 discourse thread, STH DEG1, Newegg row, MUO RX9070 OCuLink, makeuseof; raw fetch ArcheoCodix/egpu-oculink-fix README+docs/topo.md+issues/B README => pass; dead ends recorded honestly: manuals.plus 403 (official manual PDF ungetatble), kernel-parameters page window miss for pcie_aspm (replaced by the R10-S9 behavior evidence), loss-budget search ERR (marked UNVERIFIED), codeberg PREPARING_YOUR_RIG carried from §R9 => pass]
deviations: none beyond scope — read-only; only RESEARCH.md touched. One deliberate ordering change vs the launch's cause list: it ranked ASPM/L1 (b) ahead of cable (d); the direct behavior evidence [R10-S9] (aspm-off no-change, retrain no-op) forces (b) DOWN to a stability lane and (a)/(d) UP — flagged as evidence, not preference.
friction: the DEG1 official manual is unreachable (manuals.plus bot-block; Minisforum's product-info SPA has no fetchable PDF) — the requirement is carried by the Newegg manual transcription + STH + chimolog, three-way consistent, recorded as such; lspci LnkSta2 bit-name semantics vary by version so the read instruction says "capture verbatim, don't paraphrase" rather than decoding from memory.
open_questions: [which of Q5 steps 1-4 turns the read (ladder is owner-executed; step-4 bypass is the definitive one); whether the board's BIOS exposes a per-slot speed menu at all (R9-S17 trust-flag unresolved, GMKtec publishes no EVO-X3 guide); whether a degraded Gen3 training latches across warm reboots on this chipset (mechanism plausible, no source — the ritual is the test); official DEG1 manual PDF wording]
next_suggested: coord fold R10 into the tuning note's LINK section at its next touch (D34 named it the fold target): replace the now-moot "BIOS-pin" discriminator with the Q5 ladder (ritual→reseat→cable→BYPASS→BIOS), add the `d3cold_allowed=0` + `amdgpu.runpm=0` STABILITY row (with the [R10-S6] same-port precedent), and record the NOT-fixes (aspm-off/retrain-as-cure) so the record stops re-listing them; owner runs steps 1-3 tonight (zero risk) and the bypass (step 4) decides whether the DEG1 itself is the suspect — if it is, the AG02/redriver-tier swap or the TP2 §2 PEX lane become purchases, and until `LnkSta` says 16GT/s the §D8 rate model stands unchanged.
