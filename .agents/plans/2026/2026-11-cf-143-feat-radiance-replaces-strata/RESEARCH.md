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
