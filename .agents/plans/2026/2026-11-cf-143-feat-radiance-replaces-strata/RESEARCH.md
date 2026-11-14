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

---

## §R11 — Framework Desktop + Minisforum DEG1 + RDNA4 (R9700/RX-9070-class) on Linux: documented working builds and what they set

Owner round 2026-11-14, lead verbatim: "the framework desktop 16, R9700, and deg1 — I
know others have done this build successfully before." Authorities re-read first (D33–D37,
§D8/§D10, §R9/§R10); nothing established there is re-litigated — the base facts carried in:
TargetSpeed=16 pin arm CLOSED (D34), dock-first ritual FALSIFIED by the owner's own cold
boot 4d6202d9 (D35/§D10), aspm-off and retrain are NOT speed fixes (R10-S9), DEG1 passive
(R9-B1), c2/c3 = the card's own Navi bridges (R9-B4), rates on the m-model (§D10.4).
External citations R11-S#, accessed 2026-11-14; every load-bearing claim carries its
quoted clause; gaps labeled UNVERIFIED. NOTE the repo's own silence (grep this round): the
ticket has NEVER recorded which adapter/riser sits between the host's slot and the OCuLink
cable — only the DEG1 end was ever identified. That hole is §R11's headline.

### R11 VERDICT (first)

**The owner's claim is SUPPORTED — and the successful builds differ from ours in exactly
one recorded way we have never tested: every Framework-Desktop eGPU-over-OCuLink build that
reports working puts a REDRIVER-BEARING adapter card in the internal PCIe x4 slot with a
short (~30 cm) cable, or sits on a factory-native OCuLink port.** Found: Framework Desktop
+ **2× Radeon AI PRO R9700**, one "on an oculink connector on the internal x4 slot", Fedora
44, working, its instability attributed to **firmware 3.06** ("I'm attributing that change
to the latest 3.06 firmware, but it's possible that the fix was in a kernel update")
[R11-S1]; Framework Desktop + **DEG1** via "minisforum eop4a card (**with redriver**)"
[identical phrasing], card enumerated (RTX 5060 Ti, Windows driver struggle) [R11-S1];
Framework Laptop 16 + RX 9070 XT over OCuLink, "Fedora doesn't have any issue detecting
the 9070 xt and it just works" [R11-S1]; plus the two passive-path successes that frame the
boundary: native OCuLink mini-PC + DEG1 measured **7.07 GB/s** [R10-S8] and the MS-S1 Max's
"R9700 over OCuLink at **Gen4 x4** on root port 00:03.1" [R9-S10]. Conversely every
documented FAILURE/DEGRADE story on the bare passive chain matches our symptom family: DEG1
"would not enumerate" on a GMKTec M7 [R9-S16]; Jeff Geerling's DEG1 run "**picky about
generic cables and needed a ReDriver adapter for one card**" [R11-S2]; the FW16 dual-M.2
builder: "Maybe DEG1 requires specially made cables… the cable quality plays a role with
every OcuLink eGPU" [R11-S3]. **Revised first rung: OPEN THE CASE AND READ THE ADAPTER CARD
(photo/part number; redriver or plain M.2→SFF-8611 riser?) and the cable length — zero
risk, and it is the ONLY rung whose success pattern is documented on this exact
machine-class.** The BIOS-per-slot-speed rung from §R10 stays dead on this platform
(Framework's published BIOS material lists no PCIe/slot-speed menu — see Q2), but the
**firmware version check (3.06, released 2026-08-03)** is real and cheap, because
(a) 3.06 updates **AMD PI to StrixHaloPI-FP11 1.0.0.2c** — AMD PI being the platform
PCIe/memory init firmware — and fixes a PCIe-device boot hang ("Fixed a boot hang issue
occurring with specific video encoder cards") [R11-S4], and (b) the one two-R9700 Framework
owner dates the stability change to it [R11-S1].

### R11-Q1 — The found builds (table; link + quote each)

| build | chain as documented | OS | speed/workload evidence | quote (URL) |
|---|---|---|---|---|
| **Martin_Roth, Framework Desktop + 2× R9700** | "run with 2 eGPUs. One is **on an oculink connector on the internal x4 slot**… The second is using an **m.2 to PCIe x4 adapter on the rear m.2 slot**. The power supply on the oculink station powers both cards"; parts: "JMT ADT-K993G-BK7 **PCIE 5.0 X4** / M.2 NVMe to OCuLink SFF-8611 External Dock Adapter (**K993G-BK7-R29Q-30cm**)", "XRIKUI NGFF M.2 M-Key to PCIe X4 Expansion Card Adapter", "Glotrends 300mm **PCIe 4.0 X4 Riser Cable**" | **Fedora 44** | working, multi-week; instability→3.06 | community.frame.work/t/framework-desktop-with-egpu/79178 posts #13/#15 (Aug 24–25 2026), accessed 2026-11-14 [R11-S1] |
| **NappDev, Framework Desktop + DEG1** | "i got a **minisforum deg1 dock** hooked it all with to the framework desktop with a **minisforum eop4a card(with redriver)**" | Windows 11 | enumerates (RTX 5060 Ti); game-launch driver issue — not a link issue | same thread post #9, Apr 9 2026 [R11-S1]; EOP4A product: "PCIe to OCuLink Card. Features a **Redriver chip** for lossless signals. Ideal for eGPU, AI compute & external NVMe" store.minisforum.com/products/minisforum-eop4a-pcie-adapter-card, accessed 2026-11-14 [R11-S5] |
| **Deja, Framework Laptop 16 + RX 9070 XT (RDNA4)** | FW16 expansion bay + OCuLink (dual-boot 2280/2230) | **Fedora** | "**Fedora doesn't have any issue detecting the 9070 xt and it just works** unlike Windows"; Windows later hit "AMD drivers timeout error" | same thread posts #8/#10 [R11-S1] |
| **Samuel_Sylvester, FW Desktop + RTX 3090** | OCuLink, "More info to come" | — | enumerated+working claim, no speed receipt | same thread post #4, Dec 28 2025 [R11-S1] |
| **Ernie_Hobbs, FW Desktop + RX 7900 XTX** | USB4 eGPU×2, THREE enclosures "fried", then "switched to **Oculink**" | Windows | working after switch; dock-electronics mortality data point | same thread posts #3/#12 [R11-S1] |
| **chimolog (JP), GMKtec EVO-X1 (HX370) + DEG1** | factory OCuLink port → bundled cable → DEG1 | Win 11 | **3DMark PCIe feature test avg 7.07 GB/s (theoretical 8.0)** — DEG1 CAN do Gen4 x4 [R10-S8] | chimolog.co/minisforum-deg1/ (2025-04-21) |
| **daimonionnn, Minisforum MS-S1 Max + R9700 + DEG2** | factory OCuLink, "R9700 over OCuLink at **Gen4 x4 on root port 00:03.1**" (their CONTROL machine) | Win | works; the failing unit was a DIFFERENT MS-S1 (root port vanished — PBS/EVAL rabbit-hole, closed) [R9-S10] | github daimonionnn/multi-gpu-llm-toolkit doc/oculink-amd-dgpu.md |
| **our lab rig (contrast)** | internal-slot adapter (**identity UNRECORDED — see headline**) + DEG1, "LnkCap 16GT/s x4" port → **stuck `8GT/s x4`** | TW/k3s | §D10.2, 48% busy, ritual-compliant cold boot | EXPLORE §D8/§D10, DECISIONS D34/D35 |

Pattern: no published Framework-Desktop-class build runs the eGPU on a plain passive
M.2/adapter riser into a DEG1 — the two redriver-bearing adapter cards named by the
working owners (EOP4A "with redriver"; K993G-BK7, sold as "PCIE 5.0 X4" — redriver
presence on THAT SKU: UNVERIFIED) + 30 cm cable are the delta; the passive successes are
all factory-OCuLink hosts with the short bundled cable (66 cm, "Keep that cable"
[R11-S2]).

### R11-Q2 — Framework Desktop PCIe reality + BIOS options (and the "16" disambiguation)

- **Two different machines exist.** *Framework Desktop* (Ryzen AI MAX 300/395, 10×10 chassis;
  GitHub: "Framework Desktop uses a **standard size Mini-ITX Mainboard** with standard ATX
  connectors" [R11-S6]) has, per community enumeration, "4 PCIe slots: 2x M.2, 1x WiFi slot,
  **1x PCIex4**" [R11-S7: community.frame.work/t/pcie-block-diagram/70104, accessed
  2026-11-14] — that x4 slot (electrical x4; gen not officially documented — **UNVERIFIED**,
  though the working builds treat it as Gen4-class) is where Martin_Roth put his OCuLink
  connector ("the internal x4 slot"). *Framework Laptop 16* exposes "**up to 8 PCIe lanes
  (x8 PCIe 4.0)**" in its expansion bay per the community module doc, with a Framework-blessed
  direction ("Framework CEO Nrp… confirmed… 'thinking about OCuLink for the Expansion Bay'")
  [R11-S3: framework.wiki/docs/community-projects/hardware/oculink-expansion-bay-module/,
  accessed 2026-11-14]; Framework's own blog previews "the OcuLink Dev Kit"
  [R11-S8: frame.work/blog/framework-laptop-16-upgrades-and-oculink-dev-kit — full text
  NOT FETCHED (408 timeout); title/snippet only]. The owner's "framework desktop 16"
  elides the two; our root-port-00:03.1 evidence says **Desktop-family**, and the adapter
  card in our bay/slot is the unidentified link segment (Q1 headline).
- **BIOS per-slot PCIe speed: NO documented setting.** The official resources page for
  the current BIOS lists highlights + component versions only — 3.06 (released
  2026-08-03): "Update AMD PI to 1.0.0.2c… Fixed a boot hang issue occurring with
  specific video encoder cards… Resolved an issue where the iGPU memory size was
  incorrectly capped at 24 GB…" components `EC ec_306_bb3566e`, `AMD PI
  StrixHaloPI-FP11 1.0.0.2c` [R11-S4: resources.frame.work/downloads/desktop/amd-ryzen-
  ai-max-300/3.06/, accessed 2026-11-14] — no PCIe/ASPM/speed menu is documented anywhere
  in Framework's fetched material. The "Advanced → PCI Subsystem Settings → Gen4 not Auto"
  menu belongs to the **GMKtec EVO-X3** world (tldevtech, SEO-trust-flagged [R9-S17]) and
  GMKtec "does not yet publish an EVO-X3 BIOS guide" [R9-S8]. **So: our §R10/§D36 rung-4
  "BIOS/EQ, UNVERIFIED" is now demoted to documented-absent on the Framework lane
  (no menu evidence exists at all) — the live firmware lever on this platform is
  VERSION (3.06 AMD PI), not a toggle.** Say it plainly: the BIOS-pin rung is guesswork
  on this machine unless we are actually on a GMKtec-class board — which the owner's own
  "framework desktop" wording denies.
- **Any Framework Desktop "Gen4-capable but trains Gen3" report?** None found in the
  fetched record (their documented failure modes are driver/enumerate/power, and the x4-slot
  eGPU **instability** fixed by 3.06-era updates). Our Gen3-latched state therefore has
  **no published Framework Desktop twin** — which is precisely why the adapter-card identity
  (our unrecorded segment vs everyone else's redriver cards) is the rung with external
  backing.
- **Risk note for the firmware rung:** "Framework Desktop bricked after BIOS 3.06 update"
  exists (community.frame.work/t/84069 — title-level; the same 3.06 added "single-ROM BIOS
  Crisis Recovery" [R11-S4] which is its own mitigation) — flag when recommending.

### R11-Q3 — DEG1 revisions and companion parts

- **Siblings:** **DEG2** — "OCuLink (PCIe 4.0 ×4)… Thunderbolt 5 input next to OCuLink, with
  a hardware switch between them… M.2 2280 slot, a 2.5GbE port… 140 W power delivery back to
  the host. Both paths run at PCIe 4.0 x4" (2.5GbE "over the Thunderbolt 5 link" — OCuLink
  alone = GPU only) [R11-S2: computingforgeeks.com/best-oculink-egpu-mini-pc/ (Oct 19–21
  2026, prices/stock-checked), accessed 2026-11-14; spec also on minisforum.com/products/deg2].
  **AOOSTAR EG02** — OCuLink + TB5 + "150 W DC line out"; AG03 reviewed at geeky-gadgets.
  Same OCuLink generation on every sibling — no Gen5 DEG exists. **The deltas that matter
  vs DEG1 are the extras, not the link.**
- **DEG1's cable is part of the product:** "ChargerLAB measured the bundled cable at about
  **66 cm. **Keep that cable**: when Jeff Geerling ran the DEG1 from a Raspberry Pi through
  an M.2-to-OCuLink adapter, it was **picky about generic cables and needed a ReDriver
  adapter for one card**… It does not support hot-plugging, so power the dock before the
  mini PC." [R11-S2]. Plus the retail-listing "force power-on mode so the dock can start
  with the PSU" (same Newegg "ForcePowerOn" button row as R9-S13) — the closest thing to a
  user-switchable "power setting" on the DEG1; no jumper/PIN-13/PERST quirk is documented
  anywhere fetched (**UNVERIFIED** — the ritual being falsified in D35 makes any such
  requirement moot for our Gen3 state anyway).
- **Known-good adapter-tier parts (the working builds' other half):** Minisforum **EOP4A**
  "PCIe to OCuLink Card… Redriver chip" [R11-S5]; **JMT/ADT K993G-BK7** "PCIE 5.0 X4 / M.2
  NVMe to OCuLink SFF-8611" with 30 cm cable [R11-S1]; generic passive risers correlate with
  the failure side (Geerling; the FW16 thread: "Maybe DEG1 requires specially made cables.
  But in addition to that, **the cable quality plays a role with every OcuLink eGPU**. For
  example, my cheap non-DEG1 setup doesn't handle PCIe…" — snippet truncated mid-clause
  [R11-S3-adjacent: community.frame.work/t/oculink-egpu-works-with-the-dual-m-2-expansion-
  bay-module/62273 p.7 as rendered by search 2026-11-14 — exact continuation UNVERIFIED]).
  Length doctrine unchanged from R10-S2 (degradation until ~1.5 m is cable-quality-driven,
  redrivers bridge what quality can't).

### R11-Q4 — RDNA4 + Linux specifics on this class

- **Driver-side: quiet.** Fedora/FW16 "just works" for the 9070 XT [R11-S1]; the radiance
  container ships its own ROCm/kernels (ticket S16) and our host amdgpu binds and serves
  the R9700 fine (§D8) — no gfx1201 kernel/link-training defect found in any fetched
  report; older-kernel enablement version for gfx1201 NOT separately verified this round
  (moot at TW 7.3.0) — **UNVERIFIED** but irrelevant to the link.
- **The documented RDNA4-on-OCuLink-on-Linux bug family is POWER-STATE, not speed** —
  the whole reason our stability row exists: D3cold root-port bus-loss ("device lost from
  bus!") fixed by udev `d3cold_allowed=0`, BACO-variant still open, `amdgpu.runpm=0` as
  the cause-D workaround [R10-S6] — all on the SAME `00:03.1`+`1002:1478/1479` chain
  signature. Nothing there claims or fixes Gen3-vs-Gen4; `setpci`/aspm non-fixes per
  [R10-S9].
- **IOMMU:** internal record governs — `amd_iommu=off`, engine "iommu off (no IOMMU is
  registered)" + "dma copy lists IN USE", gate corrected in D28(5); no external report this
  round ties IOMMU state to Gen4-vs-Gen3 training (ROCm's own Strix-Halo page doesn't
  mention per-slot PCIe; requirement is kernel 6.18.4+ KFD patches for gfx1151 compute
  [R10-era rocm doc, unchanged]).
- **The Strix power-tie: not a Framework-exposed setting.** No Framework BIOS item for
  external-GPU power was found in fetched material; the AMD PBS option machinery exists but
  is retail-hidden, and the MS-S1 Reddit plea thread states "**Framework Desktop ships this
  same option disabled**" (+daimonionnn's diff: "Non-Eval Discrete GPU Support is disabled
  on Framework too") [R11-S9: reddit.com/r/MINISFORUM/comments/1wnkrfk… — fetched null
  (body UNVERIFIED); clause quoted from the search-rendered snippet; corroborated by
  R9-S10]. Our box prints 300 W today (D33); **re-read the engine power-cap line after any
  BIOS move** — that is the honest monitoring rule.

### R11-Q5 — What fixing the link buys, priced by external numbers

| evidence | regime | measurement | read-across to radiance-on-our-box |
|---|---|---|---|
| Geerling RTX 4090 on **PCIe 3.0 x1** (1/8 of our width AND half our gen) | Qwen3-30B Q4 fully in VRAM, generation | 41.05 → 42.51 t/s = **3.4%** penalty [R11-S2] | the portion of our decode that touches NO link (resident experts, compute) — confirms the ~35 t/s compute floor is floor, not the link |
| gpt-oss-120b, **12 of 36 layers in system RAM** (TB3 ≈2.7 GB/s vs x16) | prompt processing | 140 → 304 t/s = **54%** lost to the narrow link [R11-S2] | OUR exact failure mode by mechanism ("when some layers stay in system RAM… **the link becomes the bottleneck**"), and our regime is worse (41.52 GiB pool crossing per-use); Gen3→Gen4 ≈ the ×2 this row implies |
| ChargerLAB through a DEG1 | link | **6.0–6.7 GB/s** measured (of 7.9) [R11-S2]; chimolog 7.07 GB/s [R10-S8] | what our receipt should say after the fix: engine prefill 249→~450–500 (§D8.2 model bracketed) |
| morgwai dual-3090 (DEG1 ~6000 MiB/s + UT4G ~3600 vs TB3 daisy ~2700+2700) | layer-split, weights resident per card | "virtually identical" (70B: 17.96 vs 17.83) [R9-S3/R11-S2] | why OTHER people's LLM reports claim the link doesn't matter — none of them streams 41.5 GiB of experts per-use like our profile |
| daimonionnn TB5-vs-OCuLink same-lane-count | activations vs weights crossing | **2.7–3.3%** vs **7.9–12.8%** [R9-S3] | our m-curve (0.17–0.29 + 90–100 MiB/token churn, D10.5) says we are firmly in the "weights cross" class — link first, again |

**Honest sum:** Gen4 doubles BOTH legs' link-bound ceilings (prefill ~2× toward the
450–500 measured-class; warm decode 19.3→toward the ~35 floor, §D8.2/D29 framing) — but
note what Q5's own evidence adds now: at x4-Gen4 the *remaining* x4-vs-x16 width tax on
streamed weights persists (~1/4 of desktop slot bandwidth vs the x16 rows above), so the
140–160 class stays the TP2/x16 conversation, unchanged.

### R11-Q6 — Verdict + REVISED owner ladder (supersedes §R10-Q5/§D36 ordering; changes in BOLD)

(a) "Others have done this build successfully": **SUPPORTED** — two-R9700 Framework Desktop
on Fedora via the internal x4 slot [R11-S1] is the closest known twin; the DEG1 end works
7.07 GB/s on hosts that respect its cable/adapter tier [R10-S8]. Every documented delta
from our chain: **redriver-bearing adapter card, 30 cm cable, (one case) firmware 3.06.**
(b) Externally-backed rungs, cost order: **(1) adapter-card + cable-length ID/read (zero
risk, the ONLY rung with a same-machine success pattern to copy)** → (2) 30 cm known-Good
cable swap (Geerling/chimolog "keep that cable") → **(2b) EOP4A-class redriver card (or
K993G-BK7) — ~$30-50, the part the working builds actually use** → (3) dock-bypass
open-frame control (kept: decisive either way) → (4) firmware **3.06 check/apply** with
the brick-risk note + power-cap re-read (Q4) → (5) stability hygiene (unchanged,
D36/C14) → **DEAD: "BIOS per-slot speed" (documented-absent on Framework — Q2) and the
ritual (falsified D35) — remove both from the tuning note's ladder at next touch.**
(c) Check FIRST (one thing): `sudo dmidecode -s bios-version` + `journalctl` boot banner —
**are we pre- or post-3.06 (2026-08-03)?** — alongside the case-opening adapter ID;
both are minutes, both map directly onto [R11-S1]/[R11-S4] citations.
(d) If the redriver card + short cable + bypass STILL train Gen3: our 3.94 GB/s is this
chassis+cable+slot combination's real behavior — the published working builds will then
have no remaining delta to give us, and the honest levers are profile (pool/ctx/seqs,
§R8/D28 law) and TP2/x16 (the width rows in Q5 price that road too); record "Framework
Desktop DEG1 Gen3-latched, cause unresolved" as the ticket's own datum (we found NO
published twin of our state — that itself is a finding).

### R11 — Conflicts / UNVERIFIED (loud parts)

- **Contradiction to §R10's ladder, stated loudly:** §R10 ranked the power-sequence ritual
  #1 — D35/§D10 falsified it live; §R11 then replaces its top rung with the
  adapter-card/redriver delta backed by the working-build record [R11-S1/S2/S5]. §R10's
  mechanism content (EQ grammar, aspm non-fix, DEG1 passivity) stands; only its rung-1
  ordering is superseded — twice now, by evidence.
- **Contradiction to §R9's "best fit = host-BIOS slot pin" (D33's phrasing):** on a genuine
  Framework Desktop there is **no documented per-slot speed setting** (Q2); the tldevtech
  menu is GMKtec-world. If our machine is NOT a Framework Desktop, this reverses — the
  dmidecode/board check settles the branch in one command.
- **UNVERIFIED:** our adapter card's identity/redriver presence and cable length (never
  recorded in the ticket — the headline); K993G-BK7 redriver presence (marketing string
  only); Framework Desktop x4 slot GEN officially (community-observed x4; Framework doc not
  fetched); Framework blog Dev-Kit body (408); Reddit MS-S1 thread body (fetched null —
  clause quoted from search render); the 62273 cable quote beyond its truncation point;
  gfx1201 kernel-support version history; whether 3.06 (or its EC update) touches PCIe
  training at all beyond "AMD PI updated" + video-encoder boot-hang fix (the working-owner
  attribution is user-level, with his own kernel-update hedge quoted).

### R11 — Sources (accessed 2026-11-14)

| # | URL | What it is |
|---|---|---|
| R11-S1 | community.frame.work/t/framework-desktop-with-egpu/79178 (posts #3,#4,#6,#8,#9,#10,#12,#13,#15) | The Framework Desktop eGPU master thread: 2×R9700 on Fedora via internal x4 slot + OCuLink adapter parts list + "3.06 firmware" stability attribution; DEG1+EOP4A(redriver) build; 9070 XT Fedora "just works"; three-fried-USB4-docks then OCuLink; DDU/Code-43 Windows notes |
| R11-S2 | computingforgeeks.com/best-oculink-egpu-mini-pc/ (Oct 2026) | x4-link cost table (Geerling 3.4%; gpt-oss pp 54%; generation ~3%); ChargerLAB 6.0–6.7 GB/s through DEG1; bundled cable ≈66 cm, "Keep that cable", Geerling DEG1 "picky about generic cables… needed a ReDriver adapter"; DEG1/DEG2/EG02/K12 spec+buy guide; morgwai dual-dock comparison linked |
| R11-S3 | framework.wiki/docs/community-projects/hardware/oculink-expansion-bay-module/ | FW16 bay "x8 PCIe 4.0", community OCuLink module, Framework CEO quote on OCuLink direction |
| R11-S4 | resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.06/ | Official BIOS 3.06 (2026-08-03): "Update AMD PI to 1.0.0.2c", "Fixed a boot hang issue occurring with specific video encoder cards", iGPU-mem-24GB fix, crisis recovery; component table (EC ec_306_bb3566e / AMD PI StrixHaloPI-FP11 1.0.0.2c); no PCIe/slot-speed menu anywhere |
| R11-S5 | store.minisforum.com/products/minisforum-eop4a-pcie-adapter-card | "MINISFORUM EOP4A PCIe to OCuLink Card. Features a Redriver chip for lossless signals. Ideal for eGPU, AI compute & external NVMe" |
| R11-S6 | github.com/FrameworkComputer/Framework-Desktop (README raw) | Official: "standard size Mini-ITX Mainboard with standard ATX connectors" (mainboard docs repo) |
| R11-S7 | community.frame.work/t/pcie-block-diagram/70104 | "The desktop seems to have 4 PCIe slots: 2x M.2, 1x WiFi slot, **1x PCIex4**" + no definitive official lane map published ("wait until they release official documentation") |
| R11-S8 | frame.work/blog/framework-laptop-16-upgrades-and-oculink-dev-kit | Framework's own OCuLink Dev Kit preview (title/snippet only — 408 on fetch) |
| R11-S9 | reddit.com/r/MINISFORUM/comments/1wnkrfk/mss1_max_please_enable_amd_dgpus_over_oculink/ | Search-rendered clauses: "A retail AMD card on OCuLink has no way. Framework Desktop ships this same option disabled"; body fetch returned null — flagged |
| (inherited) | R10-S1/S6/S8/S9, R9-S3/S10/S15/S16/S17, R10-era rocm docs | carried per §R9/§R10; nothing re-fetched contradicts |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R11 appended)]
commands_run: [repo reads: DECISIONS D33-D37 full, EXPLORE §D10 (falsification record + 49/50/48% census + m-curve), STATE/C14/tuning-note ladder grep for adapter-card silence (CONFIRMED: EOP4A/K993G/redriver-card never recorded for OUR rig) => pass; global-searxng web_search (degraded mid-round: 6/10 succeeded, aborts on batch 2-3) + websearch ×2 for firmware/bay => pass; web_url_read: FW community thread (3 windows, posts #3-#16), computingforgeeks (3 windows incl the full x4-cost table), resources.frame.work 3.06 notes (2 windows), PCIe block-diagram thread, framework.wiki module doc, Framework-Desktop GitHub README raw; EOP4A/DEG2 product pages via search + partial fetch; reddit thread body fetch returned null (flagged); frame.work blog 408 (title-only, flagged) => pass]
deviations: none — read-only, RESEARCH.md only. Answered the "which machine" disambiguation the owner's "desktop 16" conflates (Desktop vs Laptop 16) with both documented, because the ladder branches on it (dmidecode settles in one command). Declared the honest negative twice: no published Framework Desktop Gen3-latch twin exists (our state is a first-report candidate), and no documented Framework per-slot PCIe menu (a ladder rung retired on evidence, not preference).
friction: searxng aborted several queries under concurrency — fell back to native websearch per the round's allowance and serialized; three primary sources stayed unreachable (reddit body, FW blog 408, 62273 quote truncation) — each quoted only at the level the rendered snippet supports, marked UNVERIFIED beyond.
open_questions: [our adapter card's identity (redriver or plain riser) + cable length — THE missing variable, zero-risk read; our BIOS version vs 3.06 (and whether the user-attributed x4-slot stability gain applies before recommending anything); whether the Desktop x4 slot is Gen4 electrically (Framework doc pending); if adapter+cable+3.06 still train Gen3 → publish our Gen3-latch as the first documented case of its shape]
next_suggested: coord re-points the tuning note's LINK ladder AT THE NEXT TOUCH (D36's own re-pointing law) to R11-Q6's ordering — adapter/cable ID and redriver card above the dead BIOS-pin and ritual rungs, firmware 3.06-check kept but re-labeled user-attributed — and hand the owner the two-minute reads (open case photo, `dmidecode -s bios-version`); fold the §D10/§R10/§R11 supersede chain into DECISIONS at the next round; everything else (stability hygiene, §R8 receipt law, TP2 road) already on record.

---

## §R12 — Framework Desktop (BIOS 03.06) + DEG1 + R9700: successful builds, and why a link with COMPLETED Gen4 equalization still sits at Gen3

Owner round 2026-11-14. Authorities re-read (D33–D37, §D8/§D10/§D11, §R9/§R10/§R11);
settled facts NOT re-litigated: ritual falsified (D35), BIOS-pin-vs-TargetSpeed closed
(D34), aspm/retrain non-fixes (R10-S9), DEG1 passive + c2/c3 = card's own Navi bridges
(§R9/§D11). NEW owner data (2026-11-14, verbatim): `dmidecode` ⇒ manufacturer
**Framework**, product **"Desktop (AMD Ryzen AI Max 300 Series)"**, BIOS **03.06**;
`LnkSta: Speed 8GT/s, Width x4 / DLActive+` and `LnkSta2: … EqualizationComplete+
EqualizationPhase1+ EqualizationPhase2+ EqualizationPhase3+ LinkEqualizationRequest-
Retimer- 2Retimers- …`; `SltCap: … HotPlug- Surprise-`; `lspci -t` dock chain
`00:03.1-[c2-c4]`, APU `00:08.1-[c5]`, NPU `00:08.2-[c6]`, **NVMe under a different root
port `00:02.5-[c1]`**. Citations R12-S#, accessed 2026-11-14; UNVERIFIED items labeled.

### R12 VERDICT (first, with the two loud corrections)

**(1) The "strange signature" is not strange — because it does not say what §R10/D34
suspected and not what the owner read into it: the four `EqualizationComplete+
Phase1/2/3+` bits in `LnkSta2` are the LEGACY 8.0 GT/s (Gen3) equalization status, and
the 16 GT/s (Gen4) equalization status lives in a DIFFERENT register.** lspci's own
decoder proves the split: base-PCIe-cap `LnkSta2` decodes `PCI_EXP_LINKSTA2_EQU_COMP
0x02 / EQU_PHASE1 0x04 / PHASE2 0x08 / PHASE3 0x10 / EQU_REQ 0x20` (introduced for the
Gen3 EQ procedure) while a separate extended capability — `PCI_EXT_CAP_ID_16GT 0x26
/* Physical Layer 16.0 GT/s */` — carries `PCI_16GT_STATUS 0x0C: EQU_COMP 0x0001 /*
Equalization 16 GT/s Complete */, PHASE1..3, EQU_REQ /* Link Equalization Request 16
GT/s */` and lspci prints it as its own block (`Phy16Sta:`) [R12-S1:
github.com/pciutils/pciutils ls-ecaps.c + lib/header.h, raw-fetched 2026-11-14]. So the
owner's paste proves **Gen3 EQ completed at 8 GT/s (which it must, for a healthy Gen3
link) and that NO 16 GT/s equalization request is pending — it is SILENT on whether
Gen4 EQ ever succeeded**. The genuinely unresolved question — "trained-then-parked" vs
"Gen4 EQ never completed at all" — is answerable in ONE free read (Q2 table, read #1):
the `Phy16Sta` status on `00:03.1` AND `0000:c2:00.0`, plus the 16GT cap's Data-Parity-
Mismatch registers. **LOUDAhead: this SUPERSEDES §R10/D34's cautious wording ("Phase-1-
only evidence … do not read as proof") — the right reading is now: all four LnkSta2
phase bits belong to the 8.0 GT/s procedure, so they are neither proof FOR Gen4-EQ
success nor even partial evidence; and it equally denies the owner's natural read
("completed Gen4 EQ but sits at Gen3") — no such paradox exists in the data yet.**

**(2) The successful builds exist — but NONE publishes a 16 GT/s receipt on this
platform, and one runs it OLDER than our BIOS:** Framework Desktop + **DEG1 + RX 9070 XT
(gfx1201!) on Linux**, llama-bench on the SAME model family (`Qwen3.8-Flash-Next`
GGUF, ROCm 10.0, 15/85 tensor-split with the 8060S): "I'm still using **bios 3.02**",
earlier boot hangups fixed by a **kernel** update ("I think updating the kernel fixed
it. I have it boot normally with Linux 6.18.9 … and Linux 7.0.13 … It still hangup for
a while before post but it boot fine"), results **pp512 324.80 ± 19.52, tg128 21.13
± 0.19 t/s**, no link-speed read posted [R12-S2: community.frame.work/t/framework-
desktop-with-egpu/79178 post #18, 2026-08-31, accessed 2026-11-14]; plus §R11's
Martin_Roth 2×R9700-on-Fedora build (also no speed receipt). **Verdict on the owner's
lead: "done successfully" = enumerated-and-serving, yes; "at Gen4 x4", NOT shown by any
Framework-Desktop report we can find.** Where Gen4 receipts DO exist they belong to
native-port hosts or redriver-assisted paths (EVO-X1 7.07 GB/s R10-S8; MS-S1 Gen4 x4
R9-S10; "needed a ReDriver adapter for one card" R11-S2). **This supersedes §R11's
firmware rung: the box is ALREADY on 03.06 — the exact version §R11 said to check —
so the check is CLOSED by fact; §R11's causal lead (Martin_Roth) self-hedged and
Frix_Rioux's working box sits on 3.02, pointing the kernel (not BIOS) as the moving
part on this product line.**

### R12-Q1 — Framework release notes, audited (no PCIe-laden fix pending)

Resources page hierarchy for "Desktop → AMD Ryzen™ AI Max 300 Series" lists **3.06, 3.05,
3.03, 3.02** only — 3.06 flagged "Released 2026-08-03 · 20.4 MB **Stable Latest**" ⇒
**nothing newer than 03.06 exists for this product today** [R12-S3:
resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.06/ (sidebar + header),
accessed 2026-11-14]. Release-note audit (fetched):
- **3.03** (2025-08-06): "Updated PD to 0.0.0E · Updated EC … dbx key … SAMSUNG's 128G
  LPDDR5 … Fixed an issue where hardware encryption on OPAL drives could cause a missing
  boot drive" — **zero PCIe/eGPU/slot content** [R12-S4].
- **3.05** (2026-04-02): "Added support for new LPDDR5 128GB modules · Resolved an issue
  causing slow boot times in GRUB and Linux environments · You can downgrade to a
  previous BIOS version" — no PCIe content [R12-S5].
- **3.06** (2026-08-03): "Update AMD PI to 1.0.0.2c … Fixed a boot hang issue occurring
  with specific video encoder cards … Resolved an issue where the iGPU memory size was
  incorrectly capped at 24 GB" + six CVE fixes; components `EC ec_306_bb3566e`,
  `AMD PI StrixHaloPI-FP11 1.0.0.2c` (§R11 fetch) — AMD PI is platform-init firmware,
  the only PCIe-adjacent thing across all four notes, and we already run it. No per-slot
  PCIe speed item exists in ANY Framework Desktop BIOS changelog fetched.
Conclusion: the firmware branch of this investigation is exhausted — 03.06 is current
AND is what §R11's success-attribution named; a working build at 3.02 out-ranks the
attribution. Kernel-side remains open (Frix: 6.18.9/7.0.13 fixed boot; our 7.3.0-1
post-dates both, boot works — the boot-hang class is not ours).

### R12-Q2 — The signature decoded, and the read-only discriminations (cost order)

Reading convention established by [R12-S1]: lspci ≥ current decodes per-speed EQ status
separately (`Phy16Sta`); the owner's grep window (`-A2`) cut the base-cap print short of
any Phy16 block even if present. Reads (ALL read-only; the two writes flagged):

1. **`sudo lspci -vvv -s 00:00:03.1 | sed -n '/Physical Layer 16.0 GT/s/,+2p'`** (same on
   `0000:c2:00.0`); if the block is absent on an older lspci: locate the cap offset from
   `lspci -vv` ("Capabilities: [xxx] Physical Layer 16.0 GT/s") then
   `sudo setpci -s 00:00:03.1 <off+0x0c>.l` — decode bits 16GT/s Status @ +0x0C:
   `0x1 EquComplete / 0x2 Ph1 / 0x4 Ph2 / 0x8 Ph3 / 0x10 LinkEquRequest16` [R12-S1].
   **Meaning:** EquComplete-**⇒ Gen4 EQ never finished → pure channel/margin problem
   (no paradox), jump straight to the redriver/cable rungs; EquComplete+ with `LnkSta`
   at 8GT ⇒ true trained-then-parked → go to read 2; `LinkEquRequest16+` on the bridge
   side = firmware/hardware asking for re-EQ — log it.**
2. **Post-EQ fallback evidence (cause a):** `sudo lspci -vvv -s 0000:c2:00.0 | grep -E
   'UESta|CESta|BadTLP|Replay'` + `journalctl -k -b | grep -iE 'aer|bad tlp|corrected
   error|replay'` + the 16GT cap's parity-mismatch registers `+0x10 Local DPM / +0x14
   First-Retimer DPM / +0x18 Second-Retimer DPM` [R12-S1]. Rising `RxErr+/BadTLP+/
   BadDLLP+` correctable counters ⇒ link ran 16 and fell back on errors (SI margin);
   all-zero with EquComplete- ⇒ never even got there — consistent with a cable/adapter
   loss budget rather than a flaky-but-live Gen4.
3. **Lane Margining readiness (cause c, read-only half):** lspci decodes cap `0x27
   Lane Margining at the Receiver` printing `PortCap: UsesDriver- / PortSta:
   MargReady? MargSoftReady?` [R12-S1]. A `+` proves the silicon supports in-band
   margining; RUNNING a margin sweep is a per-device WRITE sequence with no mainstream
   Linux tool and can briefly disturb the link — owner-decided, deferred; treat the
   flag as capability-confirmation only.
4. **Firmware/ACPI cap (cause d): searched — NO report of a Framework ACPI/DSDT slot-
   speed cap, no per-slot menu in BIOS docs, and the LnkCtl2 TargetSpeed=16 read (D34)
   already contradicts any hard cap.** Negative-verify cheaply if desired:
   `sudo acpidump -b && acpixtract -a *.dat && iasl -d dsdt.dat && grep -i -E
   'MAXL|GEN|Speed' dsdt.dsl` — owner-lane, read-only; UNVERIFIED payoff.
5. **Equalization-bypass negotiation (Gen5-era mechanism, context):** the 32GT cap
   decodes `Phy32Cap: EqualizationBypass- NoEqualizationNeeded-` + "Enhanced Link
   Behavior Control: Full Equalization required / Equalization bypass to highest rate
   support / No Equalization Needed" [R12-S1] — those knobs formalize EQ-bypass at
   32 GT/s and up; for 16 GT/s on this part the actionable state is simply EquComplete,
   which is read 1. (Quoted here so a future reader doesn't re-open "bypass suggested"
   as a theory: LnkSta2 as printed carries no such bit; it's a Phy32Cap field.)
6. **Passive-channel loss at 16 GT/s (cause e)** — practical record unchanged and
   re-confirmed: bundled DEG1 cable ≈66 cm, "Keep that cable"; generic cables "picky",
   "needed a ReDriver adapter for one card" [R11-S2]; hub length rule "doesn't matter
   much … until 1.5m" [R10-S2]. **The adapter-card tier is the platform's own answer:**
   Framework users who work around the x4 slot's reach use redriver cards (EOP4A
   "Features a Redriver chip" [R11-S5]; JMT K993G-BK7-**R29Q** — and note BCC's
   unanswered question "Did you touch any of the **switches** in the R29Q? … I can make
   my Aoostar AG01 work with an M.2-OCuLink adaptor, but **not** with the R29Q"
   [R12-S2 post #19]: the R29Q reportedly carries physical switches whose purpose is
   UNVERIFIED — if our bay already holds such a card, its switch positions are a
   literal candidate for the owner's "a setting I was supposed to enable").

**Q2 bottom line:** the observed quartet does NOT mean completed-Gen4; the first read
above collapses the branch tree — most likely outcome is `Phy16Sta: EquComplete-`
(Gen4 EQ never finished), which converts this ticket's whole EQ/speculation chapter
into the plain channel-quality lane (cable → adapter switches → redriver → bypass →
accept). If EquComplete+ AND error counters move, THEN the trained-then-parked story is
alive and the margin/parity reads (2, 3) explain it.

### R12-Q3 — Framework Desktop × OCuLink/eGPU build register (this machine, speed receipts noted)

| report (date) | chain | OS | BIOS | link/speed receipt |
|---|---|---|---|---|
| **Frix_Rioux** [R12-S2 #18, 2026-08-31] | **DEG1** + RX 9070 XT (gfx1201) via the Desktop's OCuLink path | Linux (Debian-kernels 6.18.9/7.0.13; boot hang fixed by kernel not BIOS) | **3.02** | none published; llama-bench on Qwen3.8-Flash-Next GGUF ROCm 10.0 15/85 split: **pp512 324.8 ± 19.5, tg128 21.1 ± 0.2** |
| **Martin_Roth** [R12-S2 #13/#15, 2026-08-24/25; §R11] | internal **x4 slot** → JMT **K993G-BK7 "PCIE 5.0 X4" + 30 cm** OCuLink → DEG1-class PSU-fed dock; 2nd card via M.2→PCIe adapter; 2× **R9700** | **Fedora 44** | 3.06-era ("attributing…3.06…possible…kernel update") | **no LnkSta posted** |
| NappDev [R12-S2 #9; §R11] | **DEG1** + "minisforum eop4a card(with redriver)" + RTX 5060 Ti | Win11 | — | enumerated; game-launch driver issue |
| Samuel_Sylvester [R12-S2 #4, 2025-12-28] | OCuLink + RTX 3090, "works… more info to come" | — | — | none |
| Ernie_Hobbs [R12-S2 #3/#12] | USB4 eGPUs (×3, fried) → switched to OCuLink (7900 XTX) | Win | — | survival anecdote |
| BCC [R12-S2 #19/#20] | AG01 dock works via M.2-OCuLink **but not via R29Q**; AOOSTAR vendor: "Not compatible with rx9070xt… instantaneous power consumption is too high" (vendor statement as quoted in forum) | — | — | negative-DOA data point for that combo |
| **any published 16 GT/s x4 on Framework Desktop** | — | — | — | **NONE found this round or §R11's — stated plainly.** The Gen4 receipts in-corpus are native-port (EVO-X1/MS-S1/GMKtec K12-class) or redriver-tier; Framework's own product copy calls the slot "the **PCIe x4 slot** lets you connect … 50Gbps RoCE NICs" [R12-S6: frame.work Desktop page snippet, accessed 2026-11-14] |

### R12-Q4 — Platform facts, the "16" disambiguation, and the NVMe win

- **Machine:** dmidecode settles it — **Framework "Desktop (AMD Ryzen AI Max 300
  Series)"**, the 10×10 machine, BIOS 03.06. There is no "Framework Desktop 16";
  **Framework Laptop 16** is the other product (x8 bay; community OCuLink bay module
  [R11-S3]; a custom x8 OCuLink module review headline: "…**1-2% performance hit**"
  [R12-S7: notebookcheck.net title, accessed 2026-11-14]). The owner's "16" most
  plausibly conflates the Desktop's x16-length connector with the Laptop 16 brand.
- **Slot electricals:** official Framework copy: "**The PCIe x4 slot** lets you connect
  high-speed, low-latency 50Gbps RoCE NICs like the Intel E810" [R12-S6]; third-party
  review title-level: "the **baffling PCIe x4 slot**" [R12-S8: matthewjayhunter.com
  Framework Desktop review, search-rendered, page body fetch came back empty — quote
  labeled]. Community block-diagram agrees: "4 PCIe slots: 2x M.2, 1x WiFi slot, 1x
  PCIe**x4**" [R11-S7]. **So the eGPU path is a Gen4-class x4 link by design —
  the LnkCap `16GT/s x4` we carry is the slot telling the truth; width is the platform,
  speed is the open question (Q2). x8/x16 lane counts on this machine: none exposed to
  the dock path.** §D11's "not-determinable" board identity is CLOSED.
- **Root-port layout from the new `lspci -t` — the good news, confirmed:** NVMe (the
  n-gram disk) sits under its **own** root port `00:02.5-[c1]`, separate from the dock's
  `00:03.1-[c2-c4]`; APU `00:08.1-[c5]`, NPU `00:08.2-[c6]`. **The §D11.3 open question
  ("whether c1 shares the 00:03.x upstream") is CLOSED: disk traffic and expert
  streaming do NOT contend on any shared uplink** — which removes a confounder from
  §D8's tier reasoning without changing any of its arithmetic (the disk's 3.42 GB/s
  O_DIRECT story and the link's 3.94 GB/s story were always independent terms; now
  provably so). It also re-confirms D6.6's "width is physical, speed is the defect"
  (the `link-capped` note stands).
- **`SltCap: HotPlug- Surprise-`** — no slot-event plumbing exists; matches the DEG1
  no-hotplug doctrine and [R10-S6]'s same-signature finding; nothing to enable there.

### R12-Q5 — REVISED owner ladder (external-backed vs inference, cost order)

0. **Read Q2-#1 (+2): Phy16Sta on 00:03.1 and c2:00.0, then the AER/parity counters.**
   Backed: the register split is tool-fact [R12-S1]; free; minutes; **decides which
   branch this whole problem is in.** (New — replaces §R10/§R11's implicit
   "trained-then-parked" framing until proven.)
1. **Inspect the bay: which adapter card, and its SWITCHES** (EOP4A-class redriver?
   R29Q-style DIP/slide switches — the BCC question unanswered [R12-S2 #19];
   photo + part number). Backed externally by the working-build delta (§R11 Q1/Q6) +
   the switches anecdote; inference: that our card lacks a redriver.
2. **Reseat both ends + swap to a short (≈30 cm) known-Good SFF-8611 cable** —
   backed: "Keep that cable" / 30 cm in the working builds [R11-S1/S2].
3. **Redriver-tier insert** (EOP4A "with redriver" is the Framework-Desktop-eGPU part
   the community actually used; ~$30-50) — backed [R11-S1 #9, R11-S5]; the failure
   signature it addresses is exactly `Phy16Sta: EquComplete-`.
4. **Bypass controls:** DEG1+cable+card on a native-OCuLink host (the chimolog/MS-S1
   class — if it Gen4s there, the bay-side path owns it), or dock-free open-frame on
   our bay's card. Decisive either way (unchanged §R10 rung-3 logic).
5. **Kernel-side hygiene, already ours to verify:** Frix's boot-hang was kernel-fixed
   and his working kernels are 6.18.9/7.0.13 while we run 7.3.0 — no link-speed claim
   either way; keep as a **stability** note only (`d3cold_allowed=0` + `amdgpu.runpm=0`
   row from C14/D36 stays, unchanged, explicitly NOT a throughput fix).
6. **CLOSED/DENIED rungs, stated plainly:** BIOS update — **none newer than our 03.06
   exists** [R12-S3]; BIOS slot-pin — no menu documented on this product (Q1/Q4,
   D34's TargetSpeed read); power-ritual — falsified (D35); aspm-off/retrain-as-cure/
   setpci — non-fixes (R10-S9); AG01-dock-with-9070xT-class — vendor-declared
   power incompatibility [R12-S2 #20].
7. **Terminal fork:** if reads 0-4 keep printing 8GT/s ⇒ **this bay-adapter+cable+DEG1
   passive combination does not close a 16 GT/s eye in this chassis**, publish it (our
   ticket would be the first documented Framework-Desktop Gen3-latch with the full
   register trail), and spend the money where §R11-Q5 prices it: weights-CROSSING the
   narrow link costs ~54% of pp (gpt-oss row) and defines our regime, while weights-
   RESIDENT costs ~3% (Geerling row) — a second R9700 (TP2) halves BOTH crossing terms
   by halving each rank's host-pool traffic and doubles compute; profile levers
   (§D8.5-5/D28 law) remain the no-spend fallback. **3.94 GB/s is then the honest
   ceiling and the tuning conclusions (§R8/§R9/§D8) all stand unchanged.**

### R12 — Conflicts / SUPERSEDES / UNVERIFIED

- **Supersedes (loud):** (i) §R10-D34's careful "Phase-1-only … at the trained speed"
  reading is REFINED to the tool-true statement: ALL FOUR base LnkSta2 EQ bits are the
  8.0 GT/s procedure's status; 16 GT/s status is a separate cap (0x26) whose bits
  nobody has read yet — so the round's premise "completed Gen4 EQ at Gen3 speed"
  DISSOLVES pending read Q2-#1 (no contradiction with the owner's data; a
  re-attribution of it). (ii) §R11's first-check "BIOS 3.06" rung → CLOSED as a fix
  (already 03.06; latest published; the thread's own causal claim self-hedged and a
  working build runs 3.02). (iii) §D11.3 NVMe-vs-dock upstream question → CLOSED
  (separate root port 00:02.5; the confounder is gone, §D8 math untouched).
  (iv) The launch's own framing "a link with COMPLETED Gen4 equalization still sits at
  Gen3" — challenged at the front per its instruction: the completion is Gen3's until
  `Phy16Sta` says otherwise.
- **Nothing in this round disturbs:** §D8's m-model/rate law, §R8's capacity verdict,
  §R9's APU adjudication, the C07/D24 naming machinery, or the NOT-fixes table.
- **UNVERIFIED list:** whether `Phy16Sta` reads EquComplete- on our ports (the round's
  central pending read); the R29Q's switch purposes and whether our bay carries one;
  our adapter card's identity (still unrecored — first-ladder item); Frix_Rioux's link
  speed (never posted — his 324.8 pp could be Gen3 OR Gen4 traffic, unattributable);
  the exact pciutils version that began printing Phy16Sta (worked from master;
  fallback raw-read recipe given); mjh review body (empty fetch — title quote only);
  AOOSTAR AG01/9070XT vendor claim (forum-quoted, not vendor-page); any DSDT MAXL-style
  cap (searched — none reported; the grep itself not run); LMR margining tooling on
  Linux (stated as absent by search, not proven).

### R12 — Sources (accessed 2026-11-14)

| # | URL | What it is |
|---|---|---|
| R12-S1 | raw.githubusercontent.com/pciutils/pciutils/refs/heads/master/ls-ecaps.c + lib/header.h | The decoder authority: base-cap LnkSta2 bit defines (EQU_COMP 0x02…EQU_REQ 0x20, RETIMER/2RETIMERS, CROSSLINK, FLIT) vs `PCI_EXT_CAP_ID_16GT 0x26` "Physical Layer 16.0 GT/s" with `PCI_16GT_STATUS 0x0C` = {EquComplete 0x1, Ph1 0x2, Ph2 0x4, Ph3 0x8, LinkEquRequest16 0x10} printed as `Phy16Sta:`; +0x10/+0x14/+0x18 Local/1st-Retimer/2nd-Retimer **Data Parity Mismatch** status; Secondary PCIe cap prints only LnkCtl3/LaneErrStat; LMR cap (0x27) prints `PortSta: MargReady/MargSoftReady`; Phy32Cap/Phy32Sta + "Enhanced Link Behavior Control" table (Equalization bypass / No Equalization Needed) |
| R12-S2 | community.frame.work/t/framework-desktop-with-egpu/79178 (posts #4,#6,#9,#12,#13,#15,#17,#18,#19,#20 — fetched again this round incl. pages beyond §R11's window) | The Framework Desktop eGPU thread, now including **Frix_Rioux #18**: DEG1 + RX 9070 XT + Linux, **BIOS 3.02**, kernel-fixed boot, llama-bench Qwen3.8-Flash-Next ROCm 10.0 (pp 324.8 / tg 21.1); **BCC #19** R29Q "switches" question + AG01-via-M.2 works; **#20** AOOSTAR "Not compatible with rx9070xt … instantaneous power consumption is too high"; Martin_Roth #15/#17 detail (single-PSU chain, M.2→PCIe second card) |
| R12-S3 | resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.06/ | 3.06 "Released 2026-08-03 … Stable **Latest**"; version list = 3.06/3.05/3.03/3.02 ⇒ nothing newer; component table (EC ec_306_bb3566e, AMD PI StrixHaloPI-FP11 1.0.0.2c) |
| R12-S4 | resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.03/ | 3.03 (2025-08-06) highlights: PD/EC, Secure Boot CA, LPDDR5 support, OPAL fix — no PCIe items |
| R12-S5 | resources.frame.work/downloads/desktop/amd-ryzen-ai-max-300/3.05/ | 3.05 (2026-04-02) highlights: 128GB modules, GRUB/Linux slow-boot fix, downgrade support — no PCIe items |
| R12-S6 | frame.work Desktop product page (search-rendered clause) | "The **PCIe x4 slot** lets you connect high-speed, low-latency 50Gbps RoCE NICs like the Intel E810…" — official electrical x4 statement |
| R12-S7 | notebookcheck.net "User showcases custom OCuLink X8 module for the Framework Laptop 16 with 1-2% performance hit" | Title-level; Laptop 16 (x8 bay) context for the "16" conflation |
| R12-S8 | matthewjayhunter.com/post/reviews/hardware/framework_desktop/ (search render: "the baffling PCIe x4 slot, 5GbE…70B LLMs on Linux") | Third-party confirmation of the x4 slot framing; body fetch empty → title-level only |
| (inherited) | R11-S1..S9, R10-S1..S9, R9-S10/S15/S16/S18, §D8/§D10/§D11, D33–D37 | carried; nothing re-fetched contradicted them except the re-attributions listed above |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R12 appended)]
commands_run: [repo reads (D33–D37, EXPLORE §D10/§D11 incl. its paste-ready block, §R9/§R10/§R11 re-read; grep confirms our bay adapter was never recorded) => pass; raw fetches: pciutils ls-ecaps.c (2 windows) + lib/header.h (2 windows) — LnkSta2 vs PCI_EXT_CAP_ID_16GT 0x26 / PCI_16GT_STATUS 0x0C bit map, Phy16Sta print, DPM status regs, LMR cap print => pass; web_url_read: resources.frame.work 3.03/3.05 pages (3.06 inherited verbatim from §R11), community 79178 later pages (Frix/BCC/AOOSTAR finds) => pass; searxng searches ×7 (degraded: one batch aborted; one noise-heavy) + websearch ×1 fallback => pass; mjh review body fetch returned empty and PCI_LMR offset guess untouched — both logged UNVERIFIED rather than guessed ]
deviations: none — read-only, RESEARCH.md only. The launch framed the signature as "completed Gen4 EQ at Gen3 speed"; I was explicitly invited to challenge it and DO so loudly and on-source (tool-decode authority): those completion bits are the 8.0 GT/s register; the Gen4 status is a different, unread register (0x26 cap, +0x0C) — the paradox is pending, not real. No settled ticket fact (D34/D35/§D8/§R8/§R9) was re-litigated.
friction: searxng aborted one query batch and one query returned junk (Samsung/XDA noise) — recovered via the native websearch and by re-querying; pciutils path guessing cost one 404 (file lives at repo root, not lib/) — resolved via the trees API; lspci's Phy16Sta print exists in master but the introducing version is unrecorded → the ladder ships the setpci-equivalent read so the rung never depends on distro-lspci age.
open_questions: [Phy16Sta on 00:03.1/c2:00.0 — the single read that selects the branch (EquComplete- channel problem vs trained-then-parked error problem); our bay adapter's identity and any physical switches (R29Q anecdote); Frix_Rioux's actual link speed (follow-up ask if the owner ever pings the thread); whether the 16GT parity-mismatch/DPM registers move during a Gen4 attempt]
next_suggested: coord hand the owner Q2's read-#1 (one command pair, copy-pasteable) BEFORE any hardware spend — if it prints EquComplete- the case closes as channel quality and ladder rungs 1–3 (adapter ID → short cable → EOP4A-class redriver card) execute in that order against the working-build precedent; fold the supersede lines (LnkSta2 bit-attribution; §R11 firmware rung CLOSED at 03.06-latest; NVMe-contender confounder closed) into DECISIONS + the tuning note's §1 at next touch per the D36 re-pointing law, and restate the terminal fork verbatim: if still 8GT/s after all that, publish the first documented Framework-Desktop Gen3-latch and move the money to TP2 or the §D8 profile levers — the rate model and every prior capacity verdict stand.

---

## §R13 — Gen4 equalization COMPLETED at the card, link parked at Gen3: what that signature means on a Framework Desktop + ASM1955 ReDriver + DEG1 chain

Owner round 2026-11-14. Authorities re-read (D33–D38, §D8/§D10/§D11, §R9–§R12).
SETTLED and carried without re-argument: one negotiating link (root `00:03.1` ↔ card,
past the passive DEG1 — c2/c3 are the card's own `1002:1478/1479`); TargetSpeed=16
(D34); ritual falsified (D35); aspm-off/setpci-speed denied (R10-S9); BIOS latest 03.06
with zero per-slot PCIe content (D38(2)); platform = Framework Desktop, eGPU path
electrically x4 (D38(4)); NVMe on its own root port; base-cap `LnkSta2` EQ bits are the
Gen3 procedure's (D38(1)). NEW data treated as premise: card-side
`Phy16Sta: EquComplete+ EquPhase1+ EquPhase2+ EquPhase3+ LinkEquRequest-` at cap
`[410 v1] Physical Layer 16.0 GT/s`; `Lane Margining at the Receiver` present but
`PortCap: Uses Driver- / PortSta: MargReady- MargSoftReady-`; our adapter is an
**M2-1955-OCU "ReDriver"** card (ASM1955-class — the §R12 rung-3 purchase is
redundant, retired below); `journalctl` `_OSC: platform does not support
[SHPCHotplug AER]` (firmware-withheld AER); and the owner's own correction that the
host-side Phy16 grep pattern was void, not evidence. Citations R13-S#, accessed
2026-11-14; UNVERIFIED items labeled.

### R13 VERDICT (first)

**Trained-then-parked is now REAL (card side) and, on THIS chain, it means: the
16 GT/s equalization procedure negotiated to completion — the phases only pass with the
target-rate exchange done, TI: "After completing Phase 3 … the PCIe link should have BER
less than 10⁻¹²" — and the link nevertheless settled at 8 GT/s, which TI names exactly:
the link runs "at **the fastest rate it can stably support**" [R13-S2].** Two branches
remain open and the FIRST is one free read away: (A) **post-EQ L0 instability** — the
channel held 16 GT/s through training but missed the BER target in traffic (the
redriver's presence makes "couldn't train" less likely, "marginal-at-16" more so), with
the per-16GT **Data-Parity-Mismatch** registers (cap+0x10/0x14/0x18) and `DevSta:
CorrErr+` as the evidence that does NOT need AER; or (B) **host-side non-participation**
— the root port's own 16 GT/s status (still unread — the owner's `16GT` grep could not
match lspci's `Physical Layer 16.0 GT/s` string; the void read is re-issued fixed).
**Cheapest discriminating action: the fixed host-port read block (Q4-a), then the
`remove`→`rescan` re-learn (owner-lane write) which forces a fresh full training you can
watch in `dmesg` for the 16 GT/s attempt + abort live.** And plainly: our own bay card
turns out to carry the very "ReDriver" fix §R12 recommended buying — **that rung is
retired in writing here; the recommendation was hardware they already own, said so
loudly.** What the signature does NOT support anymore: "Gen4 was never attempted" (§R12
Q5's hoped-for branch, now contradicted at the card end), and "buy a redriver" (owned).

### R13-Q1 — The spec-grounded ways a far port shows EquComplete+ Ph1/2/3 while the link runs 8 GT/s

- **(a) Speed-change/EQ machinery, per TI (SNLA415, fetched full):** equalization is
  per-generation cascade — "if all PCIe devices are Gen 5, there will be three link
  equalization processes: first to Gen 3, from Gen 3 to Gen 4, and from Gen 4 to Gen 5";
  the phases are preset-negotiation until "BER of less than 10⁻⁴" gates Phase 2 and
  Phase 3 completion targets "BER less than 10⁻¹²"; **"In some motherboard designs,
  particularly those with long channel links, this level of signal quality is not
  possible. Additional signal conditioning may be required. In this case, repeaters like
  redrivers and retimers are used"** [R13-S2]. A link that completes 16GT phases then
  parks at 8 is the spec-normal outcome when post-EQ 16 GT/s traffic cannot hold the BER
  — the LTSSM re-enters Recovery and re-establishes L0 at the last good rate ("send or
  receive data at the fastest rate it can stably support" [R13-S2]); autonomous
  re-attempts are not guaranteed, and the spec gives software two re-triggers:
  `LnkCtl3 Perform Equalization` (lspci prints the bit — `LnkCtl3: LnkEquIntrruptEn%c
  PerformEqu%c`, pciutils `PCI_SEC_LNKCTL3_PERFORM_LINK_EQU` [R12-S1/R13-S1]) and any
  hot-reset/relearn that re-runs the full sequence. The **Data Parity Mismatch** regs at
  the 16GT cap's +0x10/+0x14/+0x18 (Local / 1st / 2nd Retimer [R12-S1]) are the
  purpose-built, AER-free evidence that 16 GT/s was *lived and lost* vs *never lived*.
- **(b) Can the card's `Phy16Sta` complete while the link never ran 16 GT/s?** Only via
  **link subdivision**: a genuine retimer splits training — "the link can be split in
  two parts due to the PCIe retimer: root complex to the retimer and retimer to the
  endpoint… **The link on both sides of the retimer undergo link initialization
  separately**" [R13-S2; Intel's spec-supplement lists the concept as "Link
  Subdivision" §1.4.1 [R13-S3]]. Then the card's phases describe its own segment and the
  root port may never have finished 16GT EQ — the end-to-end speed still falls back.
  **But a present, participating retimer is DETECTED on the link and our root-port read
  says `Retimer- 2Retimers-`** (the pciutils LnkSta2 defines `RETIMER 0x0040 /
  2RETIMERS 0x0080` are exactly those detection flags [R12-S1]) ⇒ on the evidence, our
  link is NOT subdivided: the "ReDriver" behaves as an analog redriver (invisible to the
  LTSSM by design — ASMedia itself lists "Redriver" parts like ASM1468 "linear redriver …
  for PCB trace extension" in a family separate from its retimers [R13-S5]).
  Consequently the card-side completion **does** describe an end-to-end Gen4
  negotiation, and the host-side "never asked" theory is disfavored — pending read Q4-a
  to confirm the host end also completed (if it shows `EquComplete-` while the card
  shows `+`, that ASYMMETRY is itself the finding: preset-mismatch between the ends, not
  a dead channel). And for the sub-question "root port with LnkCap 16GT/s but NO cap
  0x26": that would be an incomplete Gen4 implementation (the per-speed ext caps carry
  the EQ controls a 16GT-capable DS port needs to run phases at all); lspci will simply
  not list the block — the enumeration in Q4-a settles whether it exists at all.
- **(c) Firmware/ACPI per-slot speed caps:** nothing in the spec places a *rate limit*
  in `_PLD/_UPC/_DSM` (those carry presence/power/consumer info — marked UNVERIFIED as
  a cap mechanism, no citation found this round); AMD's platform speed strap exists in
  PBS/PI but D34's `TargetSpeed: 16GT/s` read already shows the instruction is Gen4, and
  no Framework report of a silent speed-cap was found (search negative this round). The
  `_OSC: platform does not support [SHPCHotplug AER]` line (owner paste; kernel's own
  _OSC negotiation print) proves this firmware withholds AER control — it is an
  error-REPORTING withholding, not a speed cap; nothing links it to 8GT/s except by our
  own reading. **Rank: low, but non-zero only via AMD PI preset defaults — and PI 1.0.0.2c
  is current-latest with no per-slot surface (D38(2)).**
- **(d) ReDriver unpowered/disabled:** an analog redriver that LOSES power opens the
  path — the link would not train at Gen3 either (TI's conditioning is in-path for the
  high rates the platform needs it for; with a dead redriver expect degraded or dead at
  ALL rates, not a clean Gen3 with completed Gen4 phases at the far end). M.2 sockets
  supply 3.3V aux and the card is mid-chain of a LIVE link — so power-off is DISFAVORED
  by our own evidence; whether the ASM1955-class part has a mode strap/jumper: NO page
  fetched for this SKU mentions any (specs: "Built-in PCIe ReDriver to extend PCIe Gen4,
  16GT/s differential pair signals" / "PN # M2-1955-OCU" [R13-S4] — chip datasheet
  absent from public web: **ASM1955's exact function-class is UNVERIFIED**; the SKU name
  + `Retimer-` bit make analog-redriver the working read). A protocol-level retimer
  present-but-1x/bypassed would still normally set the detection bits; it doesn't here.
- **(e) Marginal passive channel at 16 GT/s:** the standing physical story (R10-S2
  "picky about generic cables", LiKenun [R13-S6]: "**been burnt by shoddy signal
  integrity for PCIe 4.0 with OCuLink cables on many occasions. Every mating interface
  you add to the chain further degrades the signal integrity**"), now RE-READ with the
  new signature: the channel trains (phases complete through the redriver) but may not
  HOLD 16GT/s in traffic — margin, not magic. Fix candidates remain per-section: reseat
  (contact impedance), shorter/better cable, socket move (different preset/pu-training
  defaults per port), open-frame bypass (shortest chain). What it is NOT anymore:
  "no redriver in path" (owned) or "never attempted" (card says otherwise).
- **Lane Margining (the tool branch):** our read shows the capability EXISTS (`[450 v1]
  Lane Margining at the Receiver`) but `PortCap: Uses Driver-` and
  `PortSta: MargReady-/MargSoftReady-` — i.e., nobody (driver or firmware) has armed
  margining software-readiness; the spec requires SW enablement to run margin steps
  (exact bit semantics UNVERIFIED this round — spec paywalled; pciutils print quoted in
  §R12-S1 shows only the presence/ready flags). **Verdict: not a dead end, but a detour:
  no mainstream Linux CLI is evidenced; the free host-read + relearn experiment answer
  90% of the question first.**

### R13-Q2 — The part itself (M2-1955-OCU / ASM1955)

- **What the SKU claims:** "M.2 M-Key PCIe Gen4 with **ReDriver** to OCulink 4i
  (SFF-8612) Adapter … Built-in **PCIe ReDriver to extend PCIe Gen4, 16GT/s**
  differential pair signals … pin-out defined by SFF-9402 Rev1.1 … Micro SATA Cables
  PN # **M2-1955-OCU**" — vendor pages (eproductsolutions render; microsatacables.com)
  [R13-S4]; connector naming SFF-8612/4i is the SlimSAS-family spelling of OCuLink 4i
  (the industry mixes 8611/8612 labels — cosmetic). **Rated: Gen4 x4, signal-conditioning
  by design; no jumper/aux-power note exists on the page ⇒ M.2-slot-powered, no user
  settings — "a setting on the card" is effectively ruled out for THIS part** (vs the
  K993G-R29Q anecdote in §R12 which reportedly has switches — different part).
- **ASM1955 as silicon:** ASMedia's public catalog separates **"Redriver"** (e.g.,
  ASM1468: "dual lanes/4 differential channels **linear redriver** … for PCI Express
  PCB trace extension") from retimer products [R13-S5]; no public ASM1955 datasheet page
  was reachable this round ⇒ **chip identity UNVERIFIED**; the SKU's own word is
  ReDriver and our `Retimer-` bit agrees — working read: analog signal conditioner,
  LTSSM-transparent.
- **Visibility:** a redriver adds NO config-space device (it is not a bridge); its
  absence from `lspci -t` (our recorded chain `00:03.1-[c2-c3-c4]`, c2/c3 = the card's
  own `1002:1478/1479`) is EXPECTED and is NOT evidence of inactivity — settling the
  §R12-Q2 "is it visible at all" question: **not visible by design; the only visible
  trace is LnkSta2's Retimer bits (which a redriver does not set and ours does not
  show) or measurement (link quality).** If it were a protocol retimer, presence would
  have set `Retimer+`. **A `1b21:` device therefore SHOULD NOT be searched for.**

### R13-Q3 — Framework Desktop M.2 reality + the speed-receipt census

- **Slots:** community block diagram (carried §R11-S7): "4 PCIe slots: 2x M.2, 1x WiFi
  slot, 1x PCIex4"; third-party reviews carry "2x M.2 2280 NVMe PCIe Gen 4x4"
  (bikmantech [§R11 search-render], mjh "the baffling PCIe x4 slot" [R12-S8];
  official frame.work copy on the card slot [R12-S6]); Framework's own help/spec pages
  did not render this round (408s — slot-gen-per-socket table UNVERIFIED officially,
  community-consistent). Our OWN lspci -t proves the operative fact: **the two M.2
  sockets ride DIFFERENT GPP root ports (`00:02.5` storage, `00:03.1` dock-path) — so
  "move the adapter to the other socket" is a real, free A/B of host-side silicon
  behavior (per-port presets/EQ state), and it does not disturb the disk tier's own
  port story** (NVMe just swaps places — boot-disk caveat: the adapter move requires
  the NVMe re-seat too; a one-time owner operation, rollback trivial).
- **How the community adds OCuLink to a Desktop (the thread the owner's build follows):**
  "Oculink Port - How to add it?" [R13-S6: community.frame.work/t/71782, accessed
  2026-11-14]: options are "a pci-e card that has the port internally" or "**Take up
  one of the nvme slots to an oculink adapter**" — i.e., EXACTLY our architecture (a
  ReDriver M.2 card in an nvme socket, or a bracket card in the x4 slot); no
  Framework-official OCuLink accessory exists for the Desktop (the blessed accessories
  are its expansion cards; an x8 OCuLink bay module exists for the LAPTOP 16 — R11-S3/
  R12-S7 — do not conflate). A photo build confirms the DIY pattern in the field:
  "Pcie 4 Oculink adaptor for framework desktop … Installed card no bracket … It's a
  bit loose on inside but hasn't failed me yet" [R13-S7: thread search-render, 2025-12-30,
  accessed 2026-11-14 — speed never stated].
- **The census, stated plainly:** of every Framework Desktop eGPU report found (§R11 +
  this round: Frix_Rioux 9070XT+DEG1 BIOS 3.02 pp324.8/tg21.1 [R12-S2]; Martin_Roth
  2×R9700 Fedora [R12-S2]; NappDev EOP4A+DEG1 [R12-S2]; Samuel_Sylvester 3090
  [R12-S2]; the photo builds [R13-S7]) — **not one publishes a negotiated link speed;
  ZERO Framework Desktop owners have documented 16 GT/s x4.** Frix's throughput
  (pp 324.8 ≈ our ~250–286 band, tg 21.1) is consistent with Gen3-class crossing
  without proving it; D38(3)'s reading hardens: **"others have done this build"
  verifiably means "done it, plausibly AT Gen3" — the claim as stated does not
  establish 16 GT/s was ever achieved on this platform by anyone.**

### R13-Q4 — Read-only command set (no AER needed), corrected + version-tolerant

Every block is read-only; the two writes are flagged and owner-lane. (Offsets from the
fetched decoder sources [R12-S1]: 16GT ext cap = ID **0x26**, status at cap+0x0C bits
`0x1 EquComplete 0x2 Ph1 0x4 Ph2 0x8 Ph3 0x10 LinkEquRequest16`, DPM at +0x10/0x14/0x18;
base-cap `LnkSta2` at `CAP_EXP+0x32.w`, `LnkCtl2 +0x30.w`, DevCtl/DevSta inside the
base PCIe cap.)

| read | command | what it proves |
|---|---|---|
| (a) host ext caps + Phy16Sta | `sudo lspci -vvv -s 00:00:03.1 \| sed -n '/Capabilities/,/^$/p' \| grep -E 'Capa\|Physical Layer'` then `sudo lspci -vvv -s 00:00:03.1 \| grep -iA1 'Physical Layer 16'` — if the grep prints nothing on old lspci: `lspci -vvv -s 00:00:03.1 \| grep Capabilities` to find the 16GT block's hex offset `N`, then `sudo setpci -s 00:00:03.1 $((N+0xC)).l` (numeric fallback; ECAP symbolic names in setpci exist on recent tools — use whichever resolves; both READS only) | root-port side of the Gen4 negotiation: EquComplete? phase bits? `LinkEquRequest16`? If the port has NO cap 0x26 while LnkCap says 16GT/s ⇒ incomplete Gen4 implementation exposed — that finding alone would explain parked-at-8 and redirect to FW/AMD PI |
| (a2) host DPM parity | `setpci -s 00:00:03.1 $((N+0x10)).l` (and +0x14/+0x18) | non-zero Local/Retimer Data Parity Mismatch = 16GT/s ordered sets were RECEIVED IN TRAFFIC and mismatched — the "lived-and-lost" marker; all zero + EquComplete+ = clean-EQ-then-polite-fallback (timeout/abort class) |
| (b) card ends | same trio on `0000:c3:00.0` and `0000:c4:00.0` | whether both pseudo-internal hops + the EP agree; the c2 read we HAVE already shows the endpoint side completed and holds no pending request |
| (c) negotiation state | `sudo lspci -vvv -s 00:00:03.1 \| grep -E 'LnkCap:.\|LnkCap2:.\|LnkCtl:.\|LnkCtl2:.\|LnkSta:.\|LnkSta2:.\|DevSta:.\|LnkCtl3:'` (same on c2) | LnkCap2 Supported Speeds Vector (16GT present?), `LnkCtl: … HWAutoWidth-/HWAutoSpeed?` + ASPM fields, `LnkCtl2: Target 16GT/s` re-check, `DevSta: CorrErr+` (Device Status is base-PCIe-cap — **works without AER**; a creeping CorrErr count on c2/c4 = 16GT traffic really errored), `LnkCtl3: PerformEqu-` current state |
| (d) error views without AER | `dmesg \| grep -iE 'pcieport 0000:00:03.1\|link is down\|speed changed\|retrain'`; `journalctl -k -b --grep='pci\|pcie' --no-pager \| head -80` | the port bus driver prints `Link Training` / `Link Down` / slot events without AER; repeated `speed changed to 8.0 GT/s`-class lines around boot = the LTSSM's own autobiography (message texts vary — grep is forgiving on purpose) |
| (e) margining | already read: `PortCap: Uses Driver- / MargReady-` | SW-enabled margining is NOT armed; arming it = device config WRITES with link-disturb potential and no mainstream Linux tool evidenced (**UNVERIFIED tooling**) — park; the free answers are (a)/(f) |
| (f) relearn experiment — **WRITE, owner-lane** | with radiance scaled to 0: `echo 1 \| sudo tee /sys/bus/pci/devices/0000:00:03.1/remove && sleep 2 && echo 1 \| sudo tee /sys/bus/pci/devices/0000:c4:00.0/../..>/sys/bus/pci/rescan` (canonical form: remove the bridge subtree, then `echo 1 > /sys/bus/pci/rescan`) — or the gentler `setpci` LnkCtl Retrain bit (retrain bit, per §R10 forencich shape; still a write) | forces a FRESH full training; watch `dmesg -w` for the Gen4 attempt + any "Equalization … failed / speed downgraded" trace in the port's own words + the post-rescan LnkSta. If a re-learn re-runs EQ and lands Gen3 again with DPM/CorrErr moving ⇒ confirmed marginal-channel; if it lands **16GT/s** once (rare) ⇒ latch/staleness class, and the PerformEqu+retrain becomes the repeatable lever (documented owner ritual until reboot) |

**Cheapest discriminating ACTION, named:** run (a)+(a2)+(c) on `00:03.1` (three
read-only commands, one minute) — the host-side `Phy16Sta` + DPM pair splits the world
into: host-EQ-failed (⇒ host-port/socket side, ladder rung "socket move" leads) vs
host-EQ-complete-but-demoted-on-errors (⇒ channel/cable side, ladder "cable then socket"
leads) vs no-cap-0x26-on-the-port (⇒ FW/PI surface — the only branch where any
firmware hunt re-opens).

### R13-Q5 — Revised ladder + RETIREMENTS

**RETIREMENTS, in writing (per the launch's instruction):**
1. **Redriver/ReDriver purchase rung — RETIRED. Our adapter IS one** ("M2-1955-OCU …
   Built-in PCIe ReDriver to extend PCIe Gen4, 16GT/s" [R13-S4]); §R12-Q5 rung 3 and the
   §R11 "EOP4A-class insert" recommendation recommended hardware the owner already owns —
   error acknowledged. (The R29Q's switches anecdote dies too: different part, and the
   BCC question was about THAT card.)
2. BIOS/firmware rungs — stay CLOSED (03.06 = latest, zero per-slot PCIe content, D38(2)).
3. Dock-first power ritual — stays FALSIFIED (D35).
4. `pcie_aspm=off` / setpci TargetSpeed overrides — stay DENIED as speed fixes (R10-S9);
   note the distinction this round draws: **`LnkCtl3 PerformEqu` + a link relearn is the
   spec-adjacent EQ RE-RUN knob** (retry the training), not a speed override (pretend
   faster) — different thing, still owner-lane.
5. "Adapter-card identity unknown" — RESOLVED (M2-1955-OCU); its invisibility in
   `lspci -t` is expected-redriver behavior, not evidence of absence (Q2).

**LADDER, probability×cost (survivors):**
0. **(a)/(a2)/(c) host-side reads — free, minutes** — splits the diagnosis (Q4);
   backs: every bit quoted from decoder sources [R12-S1][R13-S2].
1. **Socket swap** (adapter↔NVMe, one-time, trivial rollback): a different GPP root
   port with independent per-port training state; a Gen4 landing on `00:02.5` localizes
   the defect to `00:03.1`'s port/PI side; nothing to buy. (Externally unbacked —
   inference — but it is THE experiment for Q1(b)'s asymmetry branch.)
2. **Reseat + SHORT known-Good cable** (the 30 cm class Martin_Roth's working build used
   [R12-S2]; "Keep that cable"/"picky about generic cables" [R11-S2]; LiKenun's every-
   interface-adds-loss warning [R13-S6]) — channel branch.
3. **Dock bypass / open frame** (decisive separator, unchanged logic from §R10/§R12;
   the DEG1 itself measured fine at 7.07 GB/s on other hosts [R10-S8]).
4. **Relearn with dmesg-watching (f)** — owner-lane write, after radiance down; converts
   hypothesis into the port driver's own words.
5. **Hygiene rows unchanged and orthogonal:** d3cold/runpm stability pair stays on the
   book as STABILITY ONLY (D36/C14).
6. **Terminal fork (both honest):** if no sequence lands 16GT/s — the chassis+socket+
   cable+DEG1 chain cannot hold the 16 GT/s eye in traffic (trained ≠ stable; TI's
   "fastest rate it can stably support" [R13-S2] is the epitaph) ⇒ **publish ours as the
   first Framework-Desktop Gen3-latch receipt-set** and spend on the TP2 second card
   (halves per-rank crossing; §R11-Q5: weights-crossing regimes lose ~54% of pp to a
   narrow link; x4-vs-x16 wall persists per daimonionnn "Four lanes against sixteen is
   the constraint") or the §D8 profile levers (pool/ctx/seqs) at zero cost. The 3.94 →
   7.88 GB/s dream is then formally dead on this chassis and the tuning conclusion
   (link-first was right; the link's floor is here) stands corrected-but-verified.

### R13 — Conflicts / SUPERSEDES / UNVERIFIED

- **Supersedes §R12-Q2's hoped-for branch:** "most likely `Phy16Sta: EquComplete-`" is
  CONTRADICTED at the card end (it is `EquComplete+` all phases) — the trained-then-parked
  (fallback-on-margin) story is now the leading one, host-side read pending; §R12's
  ladder rung 3 (buy redriver) and its adapter-identity uncertainty are both CLOSED by
  the SKU read; §R11's redriver recommendation — retired above.
- **Corrects this round's own launch framing (accepted):** the host-port "no Phy16
  block" non-result was a grep-pattern artifact — VOID, re-issued fixed (Q4-a).
- **Preserved, untouched:** D34/D35/D36/D38's rulings, §D8's m-model and payoff
  arithmetic (only the PROBABILITY of reaching its Gen4 branch moved down and the
  diagnosis branch tree moved), §R8 capacity law, §R9 APU narrowing, the C14 note ladder
  EXCEPT the two retired lines (C14 re-touch owed: swap rung-3's "buy redriver" for
  "socket-swap + short cable", delete the EOP4A insert).
- **UNVERIFIED:** ASM1955's silicon class (no public datasheet found — vendor "ReDriver"
  + `Retimer-` bit carry the working read); whether cap 0x26 EXISTS on 00:03.1 (the
  fixed read answers it); `_PLD/_UPC/_DSM` as any speed-cap mechanism (none found;
  asserted absent is weak-evidence); LMR spec bit semantics (paywalled) and Linux tooling
  existence; Framework official per-M.2-slot lane/gen table (help pages unfetchable,
  community-consistent); Frix_Rioux's actual negotiated speed (never posted); whether a
  relearn ever lands 16GT/s once and what reverts it (the (f) experiment will tell);
  AMD PI per-port preset defaults (no public Strix-Halo knob table).

### R13 — Sources (accessed 2026-11-14)

| # | URL | What it is |
|---|---|---|
| R13-S1 | (inherited §R12-S1) raw.githubusercontent.com/pciutils/pciutils ls-ecaps.c + lib/header.h | Bit/reg authority reused throughout: LnkSta2 RETIMER 0x0040/2RETIMERS 0x0080; 16GT cap 0x26 status @+0x0C fields, DPM regs +0x10/0x14/0x18; LnkCtl3 `LnkEquIntrruptEn/PerformEqu` print; DevSta CorrErr decode; Phy16Sta print form |
| R13-S2 | www.ti.com/lit/pdf/snla415 "PCIe Link Training Overview" (SNLA415, Aug 2022; fetched, 3 windows) | The mechanism doc: per-generation EQ cascade ("first to Gen 3, from Gen 3 to Gen 4…"); phases (BER 10⁻⁴ gate to Phase 2; Phase-3-done ⇒ "BER less than 10⁻¹²"); **long-channel boards cannot hold that ⇒ "repeaters like redrivers and retimers are used"**; **retimer = split links, "The link on both sides of the retimer undergo link initialization separately"**; final: link "send[s] or receive[s] data at the fastest rate it can stably support" |
| R13-S3 | intel.com "PCIe 4.0 Retimer Supplemental Features and Standard BGA Footprint" (June 2018 PDF; TOC fetched) | Retimer-as-spec-participant authority: §1.4.1 "Link Subdivision", §1.4 "Retimer Supplemental Features Beyond PCIe 4.0 Specification" — retimers are detected protocol devices (contrast redrivers); body sections beyond TOC not extracted → content claims limited to the TOC + TI's body text |
| R13-S4 | microsatacables.com product page (search-rendered) + eproductsolutions.com (search-rendered; direct 404) | The SKU itself: "M.2 M-Key PCIe Gen4 with **ReDriver** to OCulink 4i … Built-in PCIe ReDriver to extend PCIe Gen4, 16GT/s differential pair signals … PN # M2-1955-OCU"; no power/jumper requirement stated |
| R13-S5 | asmedia.com.tw product renders (ASM1468 "8Gbps PCIe Redriver … linear redriver … PCB trace extension"; retimer categories separate) | ASMedia's own redriver-vs-retimer product taxonomy grounding the "ReDriver = analog, invisible" read; ASM1955 datasheet NOT found (UNVERIFIED) |
| R13-S6 | community.frame.work/t/oculink-port-how-to-add-it/71782 (fetched) | How the platform's owners actually do it: "Take up one of the nvme slots to an oculink adapter" / bracket card in the x4 slot; LiKenun: "been burnt by shoddy signal integrity for PCIe 4.0 with OCuLink cables on many occasions. Every mating interface you add to the chain further degrades the signal integrity"; recommends Micro SATA/Serial Cables parts |
| R13-S7 | community.frame.work "Pcie 4 Oculink adaptor for framework desktop" (search render, 2025-12-30) | In-the-field photo build of exactly this architecture ("Installed card no bracket … hasn't failed me yet") — no speed stated anywhere, consistent with the zero-speed-receipt census |
| (inherited) | R12-S1..S8 (Frix/Martin/BIOS-audit/x4-slot), R11-S1..S7, R10-S2/S6/S8/S9, §D8/§D10/§D11, D33–D38 | carried; the only reversals are the ones declared above |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R13 appended)]
commands_run: [repo reads (D33–D38 incl. D36 ladder verbatim, §D8/§D10/§D11, §R9–§R12) => pass; web_url_read: TI SNLA415 PDF (3 windows — retimer split-link, phase/BER texts, "fastest rate stably support"), community 71782 thread, Intel retimer-supplemental PDF (2 windows, TOC incl. "Link Subdivision"), microsata/eproducts SKU pages (one 404 → search-render fallback), asmedia product renders => pass; searxng ×5 (two batches partially aborted — recovered by serializing; one query returned noise-only and was dropped) + websearch ×1 (ASM1955 sweep — no datasheet, product-taxonomy finds retained) + frame.work spec page 408 (logged) => pass; §R12 decoder citations reused from fetched headers (no memory-bits used) => pass]
deviations: none — read-only, RESEARCH.md only. Where the evidence contradicted §R12, said so loudly per instruction: its "most likely EquComplete-" branch IS contradicted at the card end, its redriver-purchase rung and adapter-identity doubt ARE retired by the SKU read, and its grep void-result IS corrected. The ASM1955 chip-class stayed UNVERIFIED despite two search lanes — stated rather than guessed, and the redriver read rests on two positive sources (vendor wording + the spec-defined `Retimer-` bit) rather than on absence.
friction: ASMedia's site exposes product pages via JS-lists the reader can't walk — ASM1955's own page was not reachable at all (search found only category siblings); the Intel PDF yielded TOC not body for the subdivision section (TI carries the needed sentence); one eproductsolutions URL 404'd while the identical SKU text survived in search renders — quoted as such and labeled.
open_questions: [host-port `Phy16Sta` + DPM + DevSta reads — the branch-splitter (Q4-a/a2/c, three minutes); whether 00:03.1 even implements cap 0x26; socket-swap outcome (00:02.5 vs 00:03.1 per-port behavior); what a relearn (f) prints in dmesg during its Gen4 attempt; ASM1955's true silicon class; any Framework Desktop owner who will ever post a LnkSta]
next_suggested: coord hand the owner the Q4-a/a2/c command block (free, splits the diagnosis) and the socket-swap as rung 1 — then re-touch C14's note ladder to DELETE the retired redriver-purchase line (per D36's own re-pointing law, a falsified row must be re-pointed in the same ticket) substituting "socket swap → short known-Good cable → open-frame bypass → relearn experiment", keeping the terminal fork's economics (TP2/profile) verbatim; if the host end shows EquComplete- while the card shows +, that asymmetry is the finding of the two-day investigation and belongs in DECISIONS at the next fold.

---

## §R14 — single-R9700 radiance decode at 70+ tok/s: published evidence, the configurations, and what this rig must change to reach it

Owner round 2026-11-14, post-D44: link now **Gen4 x4** (socket swap was the fault), rates landed
**~35 t/s warm** exactly as §D8's model predicted, and the owner's claim under test: *"with radiance
and ONE R9700, people are getting 70+ tok/s."* Authorities re-read: RQ1/RQ4/RQ5, §R8 (on-card 200K
funding; 2.94 KiB/token), §R9–§R13 (link hunt, TI spec grammar), §D8 (m-model, receipts), §D10
(exit banner: 20678 dispatches / 46.2% looked-back / 36% readmits / 71.40 GiB cumulative h2d),
D28/D29/D33–**D44** (incl. D44's retraction of my per-token figure — carried verbatim below).
Citations R14-S#, accessed 2026-11-14. UNVERIFIED items labeled; nothing here moves the capacity
verdicts (§R8) or the naming/NAT lanes.

### R14 VERDICT (first)

**The 70+ reports are real, and every one we could source is NOT our comparison: either it is
the OTHER model on one card (q27-class dense, 124–130 t/s single-stream, 586–678 aggregate @
conc8 — L1T table [R14-S1]) or it is Flash-Next on TWO+ cards (fn TP2 single-stream sustained
**137 t/s**, 1103 @conc16 [R14-S1]; 4×R9600D TP4 162–175 [R14-S1]; engine's own TP2 measured
table 62.3–64.8 with MTP, 39–40 without [R14-S2]).** For **Qwen3.8-Flash-Next on ONE R9700**,
the radiance docs' own TP1 figure is the **28–29 ms decode step** ("decode step goes from 29.0
to 28.0 ms at one sequence and from 101.3 to 95.3 ms at four" [R14-S2] — the same sentence the
ticket reads as ≈35 t/s, and the docs' TP2 table shows tok/step 1.00 at 39.9 t/s ≈ 25 ms, i.e.
the ms figures are per-STEP), and **no sustained long-context single-card fn number above ~40
t/s (no spec) or the MTP-band ~50–65 (TP2-class) is published anywhere we searched** — the
llamaperf "70 tok/s" row is a 4-card **Strata** configuration (different engine, 256 GB system
RAM, Q4_K_XL GGUF [R14-S4]), and the only third-party single-card fn-class numbers in the
aggregators are llama.cpp q27 rows (29.8 t/s at 4-bit on a lone R9700 [R14-S4]). **Our ~35
post-fix is exactly where the published single-card fn-TP1 evidence sits.** The arithmetic
agrees: 70 t/s sustained at Gen4 x4 requires ≤ ~107 MiB/token crossing (7510/70), vs our
receipt-derived ~197 (m≈0.17 miss stream, §D8.2) — and closing that gap on one card means
freeing KV-backed VRAM into the expert slab, which the owner's **8×200K** envelope (D17/Q10,
the kv-resident lever) is precisely what forbids. **Answer to the owner: real — on two cards
(q27: on one); at 8×200K×1-card it is not published by anyone, including the engine's own
docs.** The cheapest honest next moves, ranked: (1) **run the fixed probe with the CPU
governor actually set to performance AND persistent — this box has NEVER been measured at
Gen4×performance-governor** (every boot to date printed `powersave` — §D6.4/D8.1/D10.1);
(2) the `stream_bytes ÷ decode_tokens` pair-snapshot (the number D44 commissioned — it says
whether what's left is wire or host); (3) the 4 KiB-span n-gram disk tier (≤10% band, RQ1;
only worth it after (1)); (4) the TP2 follow-up card, where 70+ on "radiance and R9700s"
stops being a rumor and becomes the published norm (137 t/s at two).

### R14-Q1 — The published-numbers table (links, quotes, comparability)

| # | rate | model | cards | engine/quant | context/concurrency | host & link | ngram/limits | comparability to us |
|---|---|---|---|---|---|---|---|---|
| R14-A | **137 t/s single-stream sustained**; 1103 @conc16 | **Flash-Next MoE** | **2× R9700, TP2** | radiance (creator-adjacent thread) | "sustained" single stream; conc at 16 | **Ryzen 9950X3D, 91 GB host** | disk-tier default assumed | THE likeliest source of the owner's memory — same model, but TP2; our envelope is TP1-8×200K [R14-S1] |
| R14-B | 124–130 t/s single, 586–678 @conc8 | **q27 dense** (FP8/MXFP4 27B) | 2× R9700 TP2 | radiance | same | 9950X3D | — | dense≠MoE: "The dense models are faster in single-stream… less total weight to stream per token" [R14-S1] |
| R14-C | 162–175 t/s single; 250–324 @conc8 | Flash-Next / q27 | **4× R9600D TP4** | radiance | single-stream sustained | EPYC 9575F, **512 GB** | — | 4 cards + server RAM [R14-S1] |
| R14-D | **62.3 (56.8–67.7) / 64.8 (53.2–76.5) t/s; 39.89/39.78 without MTP; 50.56/50.86 @249,939-prompt** | Flash-Next, fp8 KV | **2× 16 GB gfx1201 TP2** | radiance **v1.17.0 docs** | 2,048 tokens decoded, 1 request | docs' rig (62K/250K prompts) | streaming on/off both | the ENGINE's own measured ceiling for fn decode — and its 250K row is 50.9 t/s WITH MTP [R14-S2] |
| R14-E | **29.0 → 28.0 ms step @1 seq; 101.3 → 95.3 ms @4 seq** | Flash-Next | **1× R9700 (`--tp 1`, flashnext-tp1 flags)** | radiance docs | 1 and 4 seqs | docs creator rig (x16 class) | prefetch off→on | = ≈35.7 → 35.7… per-step t/s at tok/step 1 (≈36→35.7); our ~35 is ON this number; with MTP multiplier (tok/step 2.87–3.45 per R14-D) it COULD reach ~100 — **no TP1+MTP sustained row is published to confirm; UNVERIFIED which reading the 28–29 ms already includes** [R14-S2] |
| R14-F | 200 t/s c=1; 500 at c=8 | q27-MXFP4 | 2× R9700 | radiance | llama-style bench | guide rig | x16 Gen5 | the L1T guide headline (TP2, dense) [R14-S3] |
| R14-G | "140–160 output, ~3200 pp… **up from about 70**", 4 cards, 256 GB | Flash-Next Q4_K_XL GGUF | 4× R9700 | **Strata** (not radiance) | llama-bench class | workstation | RAM-heavy | the only literal "70→" row found; wrong engine AND four cards [R14-S4] |
| R14-H | 29.8 gen t/s | Qwen3.8-27B | **1× R9700** | llama.cpp 4-bit | llama-bench | — | — | single-card, dense, non-radiance — still no fn-on-one-card row anywhere on the R9700 aggregator page we fetched [R14-S4] |
| R14-I | **pp 324.8 / tg 21.1** | Qwen3.8-Flash-Next Q4_K_XL | **1 card (9070 XT, 16 GB!)** + 8060S split `-ts 15/85` | llama.cpp ROCm | llama-bench, FW Desktop class | BIOS 3.02 | RAM+APU side | our nearest twin build's published tg — 21 t/s, i.e. BELOW us; llama.cpp≠radiance but shows the single-consumer-AM-card fn reality [R12-S2 Frix, re-verified] |
| R14-J | "19.2 → 29.7 → 184.9 t/s" (llama.cpp default → tuned → "vLLM Radiance MXFP4") | q27 | 2× R9700 | mixed | X-post | — | — | viral progression post — dense model, dual card [R14-S5] |

**Census conclusion (stated plainly):** every sourced >70 t/s Flash-Next row involves ≥2 cards;
every sourced single-card row is either q27-dense or ≤40 t/s; the docs' own TP1 fn step-time
(28–29 ms) sits at our post-fix rate; and the llamaperf R9700 page (74 reports) surfaced no
radiance-fn-TP1 entry in the window fetched (its engine list for the card: llama.cpp/vLLM/
Strata/ExLlamaV3). If the owner has a specific 70+ single-card fn receipt, it is not in any
public source this round found — send it and we'll audit the flags.

### R14-Q2 — Doc-grounded counter semantics (what each number MEANS)

From the v1.17.0 GUIDE (fetched; the ticket's mis-read history — `0 dispatches`, `154` — makes
this the round's second-most-important section):
- **Prefetch accounting:** "Every 2048 predictions it checks the share of its copies the steps
  routed; **under 30% it rests** (no prediction, no copy) for 8192 passes… **On Qwen3.8-
  Flash-Next at `--tp 1` with the `flashnext-tp1` flags about half the copies are used**"
  [R14-S2] ⇒ **our 46.2% "looked back on routed" ≈ the doc's own TP1 norm — normal, not
  inefficiency; the 36% readmits are the heat engine re-promoting demoted units (demotion is
  cheap; the doc's design comment: "A miss… for a host-pinned unit crosses the link on the
  step's critical path", heat.h, §D8.2) — no documented tuning knob exists (D8.2(b) law:
  "nothing we ship gates the mover; nothing we ship can tune it").**
- **kv-stream counters (the D44-commissioned measurement, now doc-grounded):** "`/metrics`
  carries `kv_resident_blocks`, `kv_stream_misses_total` and `kv_stream_bytes_total`" and
  "The startup receipt's `kv streaming:` lines name the ring, the stage and the host copy"
  [R14-S2]. `/stats` carries step/budget planes (e.g. `steps_held` under `--prefill-interleave`
  [R14-S2]); the dashboard's decode tile: "`best` is the fastest window of 32 consecutive
  single-stream steps this process has run… nothing is compared until 32 have been averaged"
  [R14-S2] — the fixed probe's scoreboard.
- **kv-resident's decode effect, MEASURED by the docs: none** — "Decode is unchanged, with and
  without MTP… streaming" (their table: 39.89 off / 39.78 on; 62.3 off-MTP / 64.8 on-MTP
  @62K) [R14-S2]. **Dropping `--kv-resident` therefore buys ZERO decode and puts the QSA group
  back on the card — it would SHRINK the expert slab** (residency arithmetic below). The
  counter-claim to retire any hope here: the eager host mirror is the 8×200K enabler, and the
  docs' 250K-prompt row is where their own long-context ceiling lives (50.9 t/s, TP2!).
- **Prefix-cache cliff (explains our `cache 0` receipts):** "When the pool cannot hold the live
  sessions, it drops prefixes the next turn wanted… On Qwen3.8-Flash-Next at a 200K context
  with two ~184K-token sessions, the second turn took **173.0 s at a 0.0% prefix hit** with a
  pool too small for both sessions, and **3.0 s at 99.0%** with one large enough. The fall-off
  is sharp; `kv_util` shows a pool approaching it" [R14-S2]. Our per-request `(cache 0)` is
  the documented state of an 8×200K box whose VRAM pool funds live sessions, not retained
  prefixes (tier force-off by kv-resident anyway) — honest framing for step-6 expectations.
- **Preemption/placement flags:** `--preempt-wait-ms` "how long a preempted prefill may wait
  for its whole-recompute gate before reclaiming cache blocks and preempting lowest-priority
  running requests" [R14-S2]; embedding/tower `ram` placements are **pinned host above the
  pool**, refused when the cgroup can't hold them "after the pools, with `--host-headroom-mib`
  … default 4 GiB" [R14-S2]; ngram `auto` = "the fastest tier with room once every other
  weight is placed" and disk = "read from the container through a row cache" [R14-S2].
- **"Why is decode slow" checklist: the docs carry no such section** (searched) — the kit they
  DO ship is: the best/recent tiles, `kv_util`, the streaming/`kv_stream_*` counters, the
  prefetch resting log, and the step-time ambiguity note above. This round's Q4 table
  operationalizes that kit; anything beyond it is our inference, labeled.

### R14-Q3 — Residency, arithmetically, and the t/s-per-capability ladder

Our card today (receipts, §D8.1/D10): usable 31.86; static 5.40; **experts resident 17.76
(74% of elastic 23.89)**; **KV 4.51 = 8×200K funded (2.94 KiB/token × 1.6M)**; prefill staging
1.63; unclaimed 0.09. Expert universe: 25,078 movable units × 2.42 MiB ≈ **60.6 GiB routed** —
of which the card holds 30%, the pinned pool the rest (§D8.2). Per-token wire at Gen4 x4
(7,510 MiB/s): **70 t/s ⇒ ≤107 MiB/token ⇒ m ≤ ~0.09 at zero churn**; our warm m≈0.17 ⇒
~197 MiB/token ⇒ wire ceiling **~38 t/s** — the owner's ~35 landing is the model, not a bug.
Freeing VRAM into the slab is the ONLY single-card lever (capability cost priced per [R14-S2]):

| knob | VRAM→slab effect | m / ceiling effect | capability cost |
|---|---|---|---|
| `--max-num-seqs 8→4` | KV 4.51→~2.8 GiB, +~1.7 GiB slab (+~700 units, +5.6pp residency) | m 0.17→~0.15 ⇒ ~45–50 t/s ceiling, **with spec ~×2.9: the band that could touch 70+ UNVERIFIED as sustained** | halves the 8-session target (owner's Q10/D17 core) + the 173 s/0%-hit cliff sharpens at 4×200K live [R14-S2] |
| `--max-num-seqs 8→2` | KV→~1.6 GiB, +~3 GiB slab | ceiling ~55–60 t/s (m~0.12) | 2 sessions is not the goal — same redefinition as runbook "fewer live sessions" rung |
| `--max-model-len 200K→128K` | mirror AND KV scale (2.56→1.64M tokens; KV 4.51→~3.3 with 8 seqs) | ~ +10% on both wire legs | forfeits the trained 200K promise; catalog true-axis re-pin (R8-Q4 ladder-2 law) |
| drop `--kv-resident` | QSA back on-card ⇒ KV GROWS — slab SHRINKS | **decode documented-unchanged** [R14-S2]; mirror −~27 GiB host but wire worse | forfeits the 8×200K lever AND the ~35 we have — strictly dominated |
| `--ngram-placement ram` | frees NOTHING on-card (disk row-cache ≠ VRAM) but kills the 4 KiB-span path (+ its ~3–10% band) | +3–10% at most (RQ1) | DEAD arithmetically: 71.04+47.68 = 118.72 > 110 cap (D8.4-4) — needs the memlock drop-in AND an envelope change; TP2's host shape (~30–35 GiB pinned) is where ram-tier becomes affordable |
| `--embedding-placement ram` (already) / `--gpu-headroom-mib 96→48` | +~0.05 GiB slab only | noise | none left to take safely |
| **TP2 (second R9700)** | universe splits per rank; pool 12288×2; prefix tier affordable; L1T measured the outcome | **137 t/s sustained** [R14-S1]; docs' 62–65 @MTP-62K [R14-S2] | capital + the re-enumeration/APU/plugin laws (RQ4/TP2 doc) + D29's strata-inversion persists at ≤52 host |

**Most t/s per unit of lost capability:** for the OWNER'S stated goal (8×200K + agent traffic):
nothing single-card beats the governor fix + `stream_bytes` measurement (cost: zero capability);
after that **`--max-num-seqs 8→4` is the only knob that plausibly reaches the 70+ zone at
200K-class depth** (via spec-multiplied ~45–50 step-rate), and it spends half the session
target — an owner ruling, never a silent edit (D28 law). Everything else either dominates
negatively (drop kv-resident) or waits for the second card (TP2 = the real 70+).

### R14-Q4 — The non-wire suspects, ranked, each with its read

| rank | suspect | evidence & doc cite | read-only test (owner) | verdict |
|---|---|---|---|---|
| 1 | **CPU governor / host-gap** | box printed `powersave, epp balance_performance` at EVERY boot incl. the Gen4 one (§D10.1); engine note (carried §D8.3): per-rank serial host work "shows as **host gap between steps**"; published magnitude for MoE decode: **UNVERIFIED** (none found) | set tuned/performance + re-verify persistence ACROSS REBOOT (§D6.4 law: bare writes die), then the fixed probe's best-tile + `journalctl` powersave line gone | **the only untested zero-cost lever at Gen4 — run first** |
| 2 | **wire-vs-host unknown (the D44 number)** | docs define `kv_stream_bytes_total` [R14-S2]; mover bytes are cumulative-with-cold-load (D44) | `GET /metrics` at two points ≥10 min of steady serving: `Δkv_stream_bytes_total ÷ Δoutput_tokens` (KV leg) + `Δ` of the per-step bytes the dashboard exposes + `best` tile vs the 28 ms/step doc floor; (mover h2d needs boot-relative reading: subtract the post-warm baseline) | the ratio decides whether remaining gap is wire (≈197 MiB/token class) or host — **measure before any other spend** |
| 3 | **n-gram disk 4 KiB spans (btrfs)** | statx dioalign unsupported on btrfs (man-pages 6.19, §D6.5); "disk = … io_uring row cache (~85 MiB, O_DIRECT, ~half first-seen rows)" [S2 §4.3, carried]; miss cost = a 4 KiB direct read off the SN7100 (3.42 GB/s measured single-stream, §D6.5); published delta **3–10%** [RQ1:773–774] | request end-to-end rate with `--ngram-placement` left `auto`-resolved (disk) vs the same probe after the pack moves to ext4/XFS (owner storage lane, §D6.5-opt-a); no counter needed — the band is small | **third-order; fix #1 before entertaining #3** |
| 4 | **memlock 8 MiB** | RAM ngram tier arithmetically dead at ANY pod cap (118.72>110, D8.4-4); io_uring ring works at 8 MiB today (live `io_uring available`); k8s has no per-pod rlimit (D6.3) — node-lane drop-in only; containerd inherits the unit's limits (D6.3 precedent + repo strata-prep idiom) — an *external* authoritative doc that containerd propagates the unit rlimit was NOT separately fetched this round: **UNVERIFIED detail** (our k3s precedent [S18]/§D6.3 is the working basis) | post-drop-in: engine HARDWARE `memlock` line flips to unlimited; decode delta expected ≈ 0 | **0 tok/s today** — bundle with a planned k3s-restart window only (D28-5 law: don't oversell it) |
| 5 | **THP/compaction at 71 GiB pinned** | host prints `huge pages always (defrag madvise)` + `AnonHugePages ≈74.9 GiB` = the pinned pool IS THP-backed successfully (§D8.4-6); compact_fail/allocstall are CUMULATIVE-since-boot incl. two fill storms | 60-s idle `/proc/vmstat` delta of `compact_stall|allocstall_*` DURING the fixed probe: near-zero ⇒ not binding (the §R8-Q4 law); if nonzero mid-step ⇒ host-stall confirmed | risk is BOOT-time fill order, not per-step — mitigation already true (radiance boots first after reboot) |
| 6 | **swap 425 MiB** | mlocked pages "preventing that memory from being paged to the swap area" (mlock(2), carried R10-S2): the pinned tier cannot be the swapped bytes — they're non-pinned anon; Wilde's zram lesson [S9] | `memory.swap.current` + `pswpout` delta during probe; keep flat | watch, don't act |
| 7 | **spec settings** | fn pack carries MTP-3 (RQ0); docs measure tok/step 2.87–3.45 (R14-D/E); dense rows use 7 (`--num-speculative-tokens 7`, q27 only) [R14-S3] | `/stats` acceptance/drafter counters or the boot CONFIGURATION line — nothing to change for fn (3 is the pack's depth) | normal; do not copy q27's 7 onto fn (depth exists in the pack, not the flag) |

### R14-Q5 — Expectation, honestly, and the ordered action list

**(a) achievable at our 8×200K envelope: NO** — no published, no doc row, and the wire
arithmetic (107 vs 197 MiB/token) says the single card would have to more than halve its miss
stream to get there, which its KV budget forbids. **(b) achievable at a reduced envelope:
plausibly yes at 4×200K with MTP (the ~45–50 step-rate × ~2.9 acceptance band, UNVERIFIED as
sustained) — that is an owner capability decision, and note L1T got 137 only at TWO cards.**
**(c) single-session/short-context reports: yes — and that is what the 70+ corpus actually is
(R14-A/B/C/D tables); the q27-dense lane ALREADY exceeds 70 on one card in our own lane plan
(llama-perf q27 rows [S8]). (d) for fn-on-one-R9700 sustained long-context: not evidenced
anywhere, including the engine's own docs.**

Actions, cheapest first, each with its proving print:
1. **Governor persistence to performance + reboot-verify + fixed probe** — prints: engine HARDWARE
   line `cpu governor performance`, best-tile ms vs the 28–29 ms doc floor. [zero $]
2. **The pair-snapshot `kv_stream_bytes_total ÷ Δtokens` read** (Q4-2) — prints: MiB/token;
   ≤107 with 70 t/s means host-bound; ~190 means wire-bound; between means churn adds. [zero $]
3. **Reseat/verify the dock-side chain at Gen4 and log `LnkSta` + engine `link` line** — the new
   Gen4 state is load-stable only since 15:38Z; one long-prefill `/diagnostics` sample closes
   that. [zero $]
4. **Step-6 8-session gate + 8×200K with the fixed probe (runbook, never run)** — prints per
   §R8-Q4 thresholds; it is also the first REAL multi-session decode number to compare against
   the 1103-conc16/586-conc8 aggregate class above. [zero $]
5. **Only if owner wants 70+ this quarter: TP2** — buy card #2 (the TP2 doc §1-§14 lane; the
   137 t/s single-stream sustained [R14-S1] and the docs' 62–65+MTP long-context [R14-S2] are
   the pre-registered receipts; host ~30–48 GiB class re-opens the strata co-residency
   arithmetic (R8-Q5) and drops the mirror entirely).
6. **Deferred by arithmetic, kept on record:** ngram-ram tier (needs the memlock drop-in AND
   a smaller envelope), pack-move to XFS (≤10% class), pool-down rungs (they trade the very
   residency the speed needs — §D8.5-5 law: profile negotiation, owner call).

### R14 — Conflicts / SUPERSEDES / UNVERIFIED

- **D44's retraction carried, and completed:** my "~83–100 MiB/token" was cumulative-mover-by-
  invented-denominator — void. The replacement method is now doc-grounded (Q4-2); the
  ≤107-vs-~197 MiB/token statement above is OUR model's arithmetic re-derived from the §D8.2
  receipts (unit size 2.42 MiB × 48 × 10 × m), not a fresh measurement — it bounds the
  discussion; the stream_bytes read will replace both.
- **Supersedes nothing settled in §D8/§R8–§R13** — the ~35 landing CONFIRMS §D8.2's Gen4
  prediction (37–40 ceiling). Refines one: §D8.4-3/§D6.4's "governor = free second swing,
  magnitude unproven" becomes **the top of the action list** now the link is fixed.
- **Ladder note for coord (D36 re-pointing law):** the tuning note's LINK section is now
  DONE-FIXED (socket swap, D44); its remaining value is the §R14 action list — re-point at
  next touch: governor-persistence promoted to first, the retired hardware rungs deleted,
  `stream_bytes` added as the standing before/after instrument.
- **UNVERIFIED:** whether the docs' 28–29 ms TP1 figures include MTP (which would raise the
  single-card fn expectation band to ~80–100 short-context — no sustained TP1+MTP row
  published, ours or anyone's); any real 70+ single-card fn-TP1 receipt (send the link);
  containerd unit-rlimit propagation beyond our own k3s precedent; tuned-vs-bios governor
  persistence route (C12 AC2 lane); llamaperf's remaining 54 R9700 reports (20-window fetch);
  the exact `/stats` field names beyond the documented `steps_held`/metrics trio (the full
  field-table fetch did not return a §5.7/5.8 listing this round — carried from RESEARCH
  [S2] §5.7/5.8 access 2026-11-11).

### R14 — Sources (accessed 2026-11-14)

| # | URL | What it is |
|---|---|---|
| R14-S1 | forum.level1techs.com/t/175-t-s-on-rdna4-with-180b-models-testing-radiance-on-many-r9700s-and-r9600ds…/258397.json (posts, fetched) | THE performance table: 4×R9600D TP4 (EPYC 512GB): fn 162–175 single-stream, 250–274 @8; 2×R9700 TP2 (9950X3D, 91GB): **fn 137 single-stream sustained, 1103 @16**, dense 124–130/586–678; the dense-vs-MoE explanation sentence; token budgets/qualitative runs incl. "the less quantized the model, the better" |
| R14-S2 | codeberg.org/api/v1/repos/StillDeadcode/radiance/raw/docs/GUIDE.md?ref=v1.17.0 (fetched, 4 windows) | Engine docs @ our pin: kv-streaming measured table (39.89/39.78; **62.3 (56.8–67.7)/64.8 (53.2–76.5)** tok-step 2.87–3.45 @61,971; **50.56/50.86 @249,939**) + "Decode is unchanged, with and without…"; prefetch paragraph ("about half the copies are used" TP1; **29.0→28.0 ms @1seq / 101.3→95.3 @4**); `kv_stream_bytes_total`/`kv_resident_blocks`/`kv_stream_misses_total` metrics defs; `steps_held`; best/recent-32-step tile semantics; the 173.0 s 0.0%-hit vs 3.0 s 99.0% prefix cliff at 2×~184K; `--host-headroom-mib` 4 GiB placement gate; placement table (embedding/ngram/vram/ram/disk) |
| R14-S3 | forum.level1techs.com/t/ultimate-2x-r9700-guide-for-qwen-3-8-27b-mxfp4-200t-s-c-1-500t-s-at-c-8/257789.json (fetched; = ticket [S7], extended) | The 2-card guide: q27 "~200 tok/s single, ~500 at 8 concurrent"; launch blocks show the headline rates are TP2 (`--tp 2 --tp-wire wht6`, `HIP_VISIBLE_DEVICES=0,1`), q27-fp8 "~130 tok/s sustained", fn row "~125 tok/s", `--num-speculative-tokens 7` dense-only recipe |
| R14-S4 | llamaperf.com/gpu/radeon-ai-pro-r9700-32gb (fetched; 20 of 74 reports) | Aggregator: q27 29.8 t/s @4-bit single card; **DeepSeek V4.1 Flash: "140–160 tok/s… up from about 70 tok/s" on FOUR R9700 via STRATA** (the only literal ~70 row); engine mix on the card is llama.cpp/vLLM/Strata-heavy — no radiance-fn-TP1 row in the fetched window |
| R14-S5 | x.com/TeksEdge status 2097838715288813780 (search render) | "19.2 → 29.7 → **184.9 tok/s**" llama.cpp→tuned→radiance-class progression, q27, **dual** R9700 — the viral shape of the owner's memory, dual-card |
| R14-S6 | huggingface.co/gostar77/qwen3.8-flash-next-radiance-q5-w5dn64-bf16ple (fetched) | Community fn pack + "validated profile": **`--tp 2 --tp-wire exact --host-pool-mib 12288 --prefix-cache-mib 12288 --max-num-seqs 2 --max-model-len 262144 --num-speculative-tokens 3`** + `RADIANCE_DISABLE_VMEM=1` — the community's long-context fn convention is TP2 + prefix-tier + FEW seqs, i.e. exactly the envelope reduction our Q3 table prices |
| (inherited) | §D8/§D10 receipts; R10-S2/S9; R12-S2 (Frix pp324.8/tg21.1); S2 §4.x/§5.x/§6.1 (accessed 2026-11-11, re-fetched for the passages quoted); mlock/statx carried | comparability anchors and the model's own numbers |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R14 appended)]
commands_run: [repo reads (RQ1/Serving-envelope re-read, §R8/§R9–§R13, §D6–§D11, DECISIONS D39–D44 incl. D44's retraction verbatim) => pass; web fetches: L1T 258397.json ×2 windows (performance table found), L1T 257789.json ×2 (TP2 launch blocks), codeberg GUIDE.md @v1.17.0 ×2 fetches + 8 targeted cuts (measured tables/prefetch/metrics-tile-cliff semantics), README.md @v1.17.0 (model table), llamaperf R9700 page, HF gostar77 card, btrfs-man5 (nodatacow constraint note), codeberg issues q= (no perf issues), searxng ×8 + websearch ×1 (radiatorcat = no signal; TeksEdge/X post captured) => pass; arithmetic re-derived from §D8.2 unit sizes (1162 MiB all-miss; 107-MiB/token 70-t/s bound; 4-seq slab +700-unit sensitivity) => pass]
deviations: none — read-only, RESEARCH.md only. Per instruction the D44 retraction was carried and completed rather than re-derived: the replacement method is the docs' own `kv_stream_bytes_total`. The round's most interesting contradiction is with the launch's own hope, said plainly: the owner's 70+ claim is real but systematically TP2/dense/4-card/Strata — no sourced fn-on-one-R9700 row exceeds ~40 (no spec) / the 62–65 doc band (TP2, MTP) at long context; our ~35 is the published single-card reality, and the docs' own TP1 28–29 ms row sits exactly on it.
friction: the docs' TP1 ms-vs-tok/step ambiguity (whether 28–29 ms already includes MTP) is unresolved and load-bearing for the upper band — flagged UNVERIFIED rather than guessed, and made the first thing the stream_bytes/best-tile reads will settle; llamaperf pagination capped at 20 of 74 reports; radiatorcat surfaced no matching entity (likely a handle I couldn't resolve — recorded, not hunted further).
open_questions: [the pair-snapshot MiB/token (decides wire-vs-host for the residual 35→?); whether the docs' 28–29 ms TP1 figures include MTP; any real single-card fn 70+ receipt the owner can point to; governor-persistence effect size at our step cadence]
next_suggested: coord run the action list top-down — governor persistence (zero cost, the only untested lever at Gen4) and the Q4-2 metrics pair before ANY profile or hardware conversation; fold the §R14 census + the ≤107-vs-197 bound into the tuning note's LINK-successor section (the link is fixed; this is its epilogue), re-point the note's remaining rows per the D36 law, and if the owner still wants the 70+ class this quarter, TP2's receipts are pre-registered (137 t/s sustained, docs' 62–65 @2×16GB) and the TP2 card already carries the host-math upgrade (R8-Q5).

---

## §R15 — the n-gram RAM tier vs the KV host mirror vs the session count: what each knob requires, what it costs, and which trade actually buys decode

Owner round 2026-11-15. Authorities re-read (RQ1, §R8, §R13–§R14, §D6/§D8/§D10/§D11,
D17/D28/D29/D33–D44). The frame-resetting live measurement (this round's premise,
post-D44): **Gen4 x4 in service**, and the first REAL /metrics pair —
`kv_stream_bytes_total{in}=410,673,152` over `generation_tokens_total=2385` ⇒
**~172 KiB/token of KV-stream crossing ≈ 0.02 ms at 7.51 GB/s**, and even charging the
mover's entire cumulative `71.40 GiB h2d` to 2385 tokens caps the expert-placement leg
at ~31.8 MiB/token ≈ **4.2 ms** — against the ~28 ms step ⇒ **the wire is now ≤15% of
step time; the remaining ~24 ms is non-wire** (§D8's prefill forecast independently
confirmed at ~467 tok/s). D44's retraction stands: the old "~83–100 MiB/token"
cumulative÷unsourced-denominator bound is VOID and is NOT rebuilt here. Docs citations
R15-S# (GUIDE.md + compose profiles @v1.17.0, fetched 2026-11-15); public reports
R15-S3 (llamaperf, Nov 13–14 rows); power docs R15-S4/S5.

### R15 VERDICT (the single recommendation the docs support)

**For radiance + ONE R9700 + the owner's 8×200K envelope, the engine's own docs support
NO decode step above ~35–40 t/s (no-spec) / the documented 28–29 ms creator step — and
of the two knobs that COULD move the ~24 ms of non-wire step time, one is arithmetically
locked out by the other: `--ngram-placement ram` needs the table's 47.68 GiB free
"after the pinned host pools … under every memory cgroup … and refuses the start
otherwise" [R15-S1] (71.04 + 47.68 + 4 > 110 ⇒ refusal, our own gate arithmetic), while
dropping `--kv-resident` to make room puts the sparse group's ~6.00 KiB/token a rank of
QSA cache back on the card (~9.3 GiB at 8×200K [R15-S1]) and shrinks the expert slab
from 17.76 to ~8.5 GiB — roughly doubling the miss stream before the tier question even
matters, and the docs' measured verdict on the mirror's own speed effect is
"**Decode is unchanged**" [R14-S2/R15-S1] either way.** The `--max-num-seqs 8→4` trade
moves ≤15%×~8% of step time — visible nothing, because the wire stopped binding.
**The two actions the docs+measurement DO support: (1) make EPP=`performance` persistent
and re-run the fixed probe — the box has run every boot at `balance_performance`
(the engine's conflated "cpu-governor" note is about EPP, and the kernel docs say the
governor NAME `powersave` is normal under amd-pstate-epp [R15-S4] — so this is the one
untested lever against the host-thread half of the 24 ms, at zero capability cost; print
it with `energy_performance_preference` + the best-tile ms); (2) if the goal is actually
>40–70 t/s sustained multi-turn on this model, the documented configuration for that is
TWO cards: the creator's own `flashnext.yaml` TP2 profile serves `--max-num-seqs 8
--max-model-len 200000` WITHOUT streaming (prefix tier `--prefix-cache-mib 4096`), the
measured TP2 rows run 62–65 t/s with MTP at long prompts [R14-S2], L1T measured 137 t/s
sustained [R14-S1] — and at TP2's host shape (pool 2×12288, no mirror) the n-gram RAM
tier finally fits (~83 GiB ≤ 110) and its documented benefit ("a step has no host work")
becomes reachable. Every published single-card fn number above ~40 t/s is another engine,
another quant, or offload (Q4 table) — none contradicts the docs' TP1 floor.** Stated
per the round-law: no change below spends the 8×200K envelope without saying so in the
same sentence — and the ones that would spend it are named and rejected here.

### R15-Q1 — `--ngram-placement ram` / `ram=DIR`: requirements and benefit, verbatim

- **What it is/needs** [R15-S1, GUIDE §4.3 lookup-tables block]: "An n-gram table
  (Qwen3.8-Flash-Next's is 47.7 GiB) is read a few rows a token. **`disk` reads rows from
  the container through a row cache with direct reads on the host; about half of a step's
  rows are first-seen, so steps wait on the drive.** `ram` copies the table into host
  memory at load (12 to 40 s more startup, depending on the page cache) and **the card's
  gather kernel reads the pinned copy, so a step has no host work.** … **`ram` needs the
  table's size free after the pinned host pools and the prefix cache's host tier, with
  `--host-headroom-mib` to spare (default 4 GiB), under every memory cgroup the process
  sits in, and refuses the start otherwise.** `auto` takes the first of vram, ram and
  disk that holds the table. **Without a device kernel for the gather (no libr4d)** the
  table is read on the host: … `ram` is a copy in locked huge pages, which **also needs a
  memlock limit that large** (`--ulimit memlock=-1`/`LimitMEMLOCK=infinity`)."
  ⇒ correction of a drift inside our own record: **the memlock gate belongs to the
  no-libr4d host-gather fallback; our box (radiance image ships libr4d for gfx1201) dies
  on the cgroup-free-space gate, not on the 8 MiB rlimit** — the engine's live note
  "the memlock limit is one of the things that keeps `--ngram-placement auto` off it"
  (§D6.3) is the engine hedging both paths; the binding one here is the first.
- **`ram=DIR`** [R15-S1]: "makes the pinned copy a file, `DIR/ngram-<id>.tab`, in a
  tmpfs, mapped MAP_SHARED and pinned for the cards … **two engines on separate card
  sets (`ROCR_VISIBLE_DEVICES`) hold one table in host memory.** The first engine …
  fills the file; a second … checks samples … and only pins it. The `<id>` is a hash of
  the container's path, size and mtime and the table's place in it." (= the TP2-era
  fn+q27 co-residency lever; per-process pin accounting + `amdgpu.no_system_mem_limit=1`
  caveat carried from RQ1 [S2].)
- **Measured benefit:** the docs publish the disk-vs-ram DELTA only qualitatively
  ("steps wait on the drive" vs "no host work"); no % figure in GUIDE. Community band
  3–10% carried [RQ1: bigcherry "moving the n-gram table to disk costs about 10%",
  L1T voices ~3%]. **On this rig's NEW numbers the stakes are clearer than % of rate:
  disk-tier step-waits are exactly the class that can hide inside the ~24 ms non-wire
  residue** — worth knowing, unreachable at 8×200K (below).
- **Does the mirror-drop make it fit?** NO twice over: gate math
  `110 − 47.68 − 4 = 58.3` needed "after the pinned host pools" vs pool+placement+arena
  ≈ 46 GiB even with the mirror gone ⇒ ~12 GiB margin − 47.68 table ⇒ **refusal**;
  AND the on-card consequence above (QSA ~9.3 GiB eats the slab; docs' own direction
  sentence: streaming's "VRAM it gave up went to the expert slab" — reversing it
  reverses the gift). **The ram tier is TP2-era hardware arithmetic, not a
  single-card flag** (TP2 host: 24+4+~3+47.68+4 ≈ 83 ≤ 110 ✓, mirror optional —
  flashnext.yaml serves 8×200K on two ranks WITHOUT `--kv-resident` [R15-S2]).

### R15-Q2 — `--kv-resident`: purpose, costs, prefix-tier relation (all doc-quoted)

- Purpose [R15-S1 §4.4.1]: "keeps the whole KV cache of the model's sparse attention
  group in pinned host RAM and only a ring of N tokens on the cards. Each decode step
  makes the blocks it selected resident, copying in the missing ones and evicting the
  coldest; an evicted block is already in the host copy. **Prefill reads the cache one
  layer at a time from the host copy. The ring is a fixed size at any context length,
  so the context is no longer bounded by VRAM**: holding two 262k-token conversations
  on two 16 GB cards, the cache went from 3.84 GB of VRAM a card to 0.74 GB of VRAM and
  3.22 GB of host RAM, **and the VRAM it gave up went to the expert slab.**"
- Costs, doc-exact: ring "6.00 KiB a token a rank at fp8 … 192 MiB at 32,768"; prefill
  stage "512 B a token a rank"; host copy "`--max-num-seqs` × `--max-model-len` tokens
  per rank"; "The VRAM pool is the larger of ring and stage, not their sum"; ring
  minimum: "Use 32,768 … and to one decode step's selection (max-num-seqs × (1+spec) ×
  513 blocks)"; "At or above max-num-seqs × max-model-len the ring covers the context
  and nothing streams."
- **Speed effects, doc-measured (their own table [R14-S2/R15-S1]): decode UNCHANGED**
  (39.89 off / 39.78 on; 62.3 / 64.8 with MTP), **prefill +1–2%** (2722→2783 @62K;
  2635→2669 @250K), perplexity +0.5% [RQ1 carried]. So kv-resident is a CAPACITY flag,
  not a speed flag — dropping it is not "faster host-free decode", it is a slab loss
  (Q1) that pays nothing back on either leg.
- Prefix-tier relation [R15-S1]: "**The prefix cache's host tier
  (`--prefix-cache-mib`) is turned off while a group streams; prefix hits still work
  from VRAM (§4.8)**" — and §4.8's measured cliff (carried §R14: "the second turn took
  **173.0 s at a 0.0% prefix hit** with a pool too small for both sessions, and **3.0 s
  at 99.0%** with one large enough; the fall-off is sharp; `kv_util` shows a pool
  approaching it") plus §4.8's own purpose line [RQ1: "Restoring a 200K-token turn
  costs a copy over PCIe; recomputing it costs minutes"]. **For the owner's 37-message
  agent workload the doc-favored shape is the prefix tier** (idle-turn resume is its
  literal use-case) — but at 8×200K on one card the VRAM backing is exactly what
  streaming exists to free, so the honest read is: **we are on the docs' capacity lane
  and pay the documented multi-turn cliff (our `cache 0` receipts) — switching lanes
  drops either the sessions or the context, and at TP2 both lanes fit (creator profile
  = 8×200K + prefix tier + no streaming).**

### R15-Q3 — Seq/context arithmetic: does freed KV reach the slab, and what does it buy?

- Docs' elastic law [R15-S1]: "**The KV pool is always elastic.** It holds the blocks
  in use plus a buffer … and **the expert plane grows into what it releases**, so a
  model whose experts do not fit never streams weights to pay for unused cache" +
  "The cache takes the rest, **up to what it could ever address (`--max-num-seqs` ×
  `--max-model-len`)**, and lends every block no live request holds back to the expert
  slab in place" + "The cache never gets less than one `--max-model-len` sequence" +
  the direction law "with a lending cache, **a larger `--host-pool-mib` takes experts
  off the card and gives the cache more**" (symmetrically: a smaller cache-addressing
  frees slab). ⇒ **YES, halving seqs flows KV→slab automatically; no doc minimums tie
  `expert_tiered` to seq count** (docs say none; `--deterministic` is the only stated
  placement killer [R15-S1]).
- Size of the prize at OUR post-Gen4 state: 4×200K frees ≈2.3 GiB KV ⇒ +~950 slab units
  (2.42 MiB each) ≈ +3.8 pp residency ⇒ m≈0.17→~0.155; the wire leg was ≤15% of step
  ⇒ step change ≈ −1% — **noise, because we are at the compute/host-thread floor the
  docs themselves print: "the decode step goes from 29.0 to 28.0 ms at one sequence"
  (creator TP1) [R14-S2/R15-S1]**. Our ~35 t/s IS that 28–29 ms norm (the ticket's
  standing reading); whether those ms figures already include MTP is **UNVERIFIED** (the
  flashnext-tp1 flags DO ship `--num-speculative-tokens 3`, and their measured TP2 rows
  show tok/step 2.87–3.45 — if the TP1 ms are per-step-with-MTP, the creator's
  single-card expectation is ~80–100 t/s and OUR 35 would say something is still wrong;
  if they are per-token, 35 IS the norm. **The best-tile + `accept` counters in one
  fixed-probe run settle which world we are in — that read is this round's one open
  experiment, and it is free**).
- `--num-speculative-tokens`/`--max-num-batched-tokens` step-cost, doc-quoted: MTP
  drafts "3 tokens in 3 serial passes" with the tok/step table above (the ×1.6
  long-context multiplier); batched-tokens is the PREFILL lever ("A prefill step copies
  every pooled expert across the link once… a 4096-token step amortises that copy over
  twice the tokens of a 2048-token one (26K prompts: **2545 vs 1413 tok/s**)"
  [R15-S2 yaml header]) + `--prefill-interleave/--busy-prefill-chunk` protect decode
  cadence (`steps_held` [R15-S1]). Neither changes decode step floor directly.
- **Answer to "is decode compute-bound now?": per the docs' own TP1 reference and our
  ≤15%-wire measurement — effectively yes; the doc-supportable single-card decode lever
  left is whatever the 24 ms host-side residue contains (EPP, ngram disk-waits), and
  neither is a session/context knob. No tier change moves the 28–29 ms floor.**

### R14→R15-Q4 — Published single-card fn >40 t/s: the complete table (headline stated)

| report | engine | card | quant | rate | context/notes | why it is not our config |
|---|---|---|---|---|---|---|
| RTX 5090 (Nov 14, 2026) | **basalt** | 1× 32GB | **NVFP4 + int8 KV** | **297.7 t/s** (their own table: spec-rows 170–387) | 16K/64K | different engine + NVFP4 weights + NVIDIA [R15-S3] |
| RX 9070 (Nov 14, 2026) | **Strata** | 1× 16GB | **IQ2 GGUF** | **60.0 t/s** | "Ryzen 7 5800X, 48 GB DDR4-2133, NVMe" — "frames the run as a joke" | 2-bit-class quant + RAM-offload engine + 16GB card — not 32GB gfx1201, not radiance [R15-S3] |
| M5 Ultra 256GB (Nov 14) | oMLX | Apple SoC | oQ8e + n-gram offload | 100 t/s (130k–200k ctx) | 3 concurrent | Apple unified 256GB [R15-S3] |
| DGX Station GB300 (Nov 13) | SGLang | ~250GB VRAM | NVFP4 | 221 t/s | single-stream | server silicon [R15-S3] |
| 2×R9700 llama.cpp-TP (Nov 13) | llama.cpp patched | **2 cards** | BF16_P12 packed | 91.4 best, 73.0–80.9 with MTP | 512-token prompts | two cards, other engine [R15-S3] |
| 2×R9700 radiance (L1T) | radiance | **2 cards** | iq4r | 137 sustained | TP2 | two cards [R14-S1] |
| docs' own 2×16GB TP2 | radiance | **2 cards** | iq4r | 39–40 no-spec / 62–65 MTP | 62K/250K | two cards [R14-S2] |
| **radiance, 1× R9700/gfx1201, this model** | **radiance** | **1× 32GB** | iq4r (113.6 GiB pack) | **none found — creator docs' TP1 reference = the 28–29 ms step (≈35 t/s); our post-Gen4 ~35 IS the published ceiling class for this exact stack** | — | — |

**HEADLINE (say it plainly):** there is **no published radiance-FP8/IQ4R Flash-Next
decode above ~40 t/s on one 32 GiB gfx1201 card**, at any context length, in any source
this round reached — every >40 row is a different engine, a smaller quant, or ≥2 cards.
The owner's "70+ on one R9700" is, on the evidence, either the dense q27 lane (which
DOES exceed 70 single-card territory in creator aggregates [S5/S8]) or TP2 rows
misremembered as single-card. **Stop optimizing toward 70+ on one card for iq4r fn:
the docs' own floor is where we are.** (UNVERIFIED: the MTP-or-not reading of the
28–29 ms row — one free best-tile probe decides it, per Q3.)

### R15-Q5 — EPP persistence, short and cited

- The governor NAME is not the problem: kernel amd-pstate docs describe active-mode
  EPP operation with the dynamic preference listed "while running under the
  **powersave** governor" — `powersave` + `amd-pstate-epp` + EPP IS the intended mode;
  the engine's "cpu governor powersave" note conflates the name with the lever
  [R15-S4: docs.kernel.org/admin-guide/pm/amd-pstate.html, fetched 2026-11-15].
- **EPP is the lever:** `energy_performance_preference` — "Lower epp values shift the
  bias towards improved performance"; `default` = "set by platform firmware"; a
  `dynamic` mode exists which "will register with the platform profile handler to
  receive notifications of user desired power state" — i.e., a desktop-side power
  daemon (power-profiles-daemon class) legitimately rewrites EPP at boot/on events and
  is the standard reason a `cpupower`-enabled box reads `balance_performance` anyway
  [R15-S4]. (ppd's exact profile→EPP table could NOT be fetched (gitlab sign-wall) —
  **UNVERIFIED mapping**; the one-command owner read settles who owns the box:
  `systemctl is-enabled power-profiles-daemon tuned tlp cpupower` +
  `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` after each
  candidate service is restarted.)
- Persistence routes that survive reboot on Tumbleweed, ranked: (1) if ppd present:
  `powerprofilesctl set performance` (the daemon re-asserts its profile; fighting it
  with cpupower is the fight the owner is losing); (2) mask competing daemons and
  restore cpupower state at boot (`cpupower frequency-set --set-epp performance` + its
  systemd unit's save/load — cpupower(1) man NOT re-fetched this round: mechanics
  **UNVERIFIED**, the read above costs less than the man page); (3) tuned's EPP
  profile if tuned is installed; (4) brute durable: a tmpfiles.d line writing
  `performance` to the per-CPU `energy_performance_preference` at boot (standard
  mechanism; existence of that unit is verified any box has tmpfiles.d — the write
  itself is owner-decided). **Print that proves it worked: the engine's own next-boot
  line flips to `energy preference performance` AND the fixed-probe best-tile drops
  below the 28–29 ms reference.** The host-gap sentence (GUIDE, carried §D8.3) is why
  a per-step host thread is EPP-sensitive on MoE serving.

### R15 — Conflicts / corrections / UNVERIFIED

- **Correction to §R14 carried forward, amplified:** with the first real /metrics pair
  in hand, the wire term measured ≤15% of step — §R14's residency-ladder table stays
  valid but its motivation inverts: seq/ctx knobs once bought wire back; post-Gen4 the
  wire is no longer where the time is. The ≤107-vs-197 MiB/token bound from §R14 is
  superseded as a DECISION input (kept as history) by this round's direct measurement —
  and, per D44, it must never be quoted as a capability bound.
- **Corrections to our own record:** memlock 8 MiB is not what blocks the ram ngram
  tier (Q1: the cgroup-free gate is; memlock matters only in the no-libr4d host-gather
  fallback) — the §D6.3 engine note overstated memlock's role for OUR image;
  "fix the governor" language retires (Q5 — EPP, not governor name).
- **No contradiction** with §R8's capacity law, the naming lane, or TP2 docs — §R15
  only adds that TP2 is where both the prefix-tier resume AND the ngram-ram tier (and
  therefore the docs' >40 decode regime) become jointly reachable, reinforcing TP2 as
  the performance answer (its doc receipts 62–65/137 t/s).
- **UNVERIFIED:** the ppd→EPP mapping (service ownership read substitutes); cpupower
  save/restore flag mechanics; whether the 28–29 ms TP1 row includes MTP (the free
  best-tile probe decides); the exact QSA on-card bytes at 8×200K if streaming is
  dropped (ring-cost 6.00 KiB/token is the doc's per-rank figure — 9.3 GiB is our
  multiplication); that libr4d's gather kernel is in the radiance 1.17.0 image for
  gfx1201 (inferred from the image's own kernel-library story [S1/S3 DOCKER.md] — the
  live boot prints do not name the gather path); any radiance single-card iq4r >40 t/s
  receipt existing beyond this round's search space (searched: llamaperf model+GPU
  pages, L1T ×3 threads, codeberg issues/README/GUIDE/compose, HF, X — none).

### R15 — Sources (accessed 2026-11-15 unless noted)

| # | URL | What it is |
|---|---|---|
| R15-S1 | codeberg.org/api/v1/repos/StillDeadcode/radiance/raw/docs/GUIDE.md?ref=v1.17.0 (fetched, §4.3 + §4.4.1 + §4.5 windows) | The placement/kv-resident doc set verbatim: ngram table size + disk "steps wait on the drive" + ram "no host work" + the cgroup-free gate + memlock-fallback clause + ram=DIR sharing; §4.3 elastic/lending/headroom/never-less-than-one-sequence laws + "larger pool ⇒ fewer resident experts"; §4.4.1 purpose ("context no longer bounded by VRAM", VRAM-given-up→slab), ring/stage/host-copy costs, ring minimums/raise rules, prefix-tier-off-while-streaming, metrics names; steps_held/prefill-interleave semantics |
| R15-S2 | codeberg.org/.../raw/deploy/compose/flashnext-tp1.yaml?ref=v1.17.0 (fetched) | The creator's ONE-card profile, header verbatim: 42 GiB pool, "process pins about 49 GiB of host memory and wants a host with 64 GB of RAM", n-gram disk, "prefill step copies every pooled expert… one-card prefill is link-bound", 2545 vs 1413 tok/s chunk law, "At 4 sequences the cache holds 301K tokens, one and a half 200K-token sessions"; flag list (no kv-resident; prefix-cache-mib 4096) |
| R15-S3 | llamaperf.com/model/qwen3-8-flash-next (fetched, 3 windows; Nov 13–14 2026 reports) | The single-card census: basalt/RTX-5090 NVFP4 297.7 (spec-rows 170–387); **Strata/RX-9070 IQ2 60.0 t/s on a 5800X+DDR4 (RAM-offload framing, "joke" attribution)**; oMLX/M5-Ultra 100 @130–200K; SGLang/DGX 221; llama.cpp-TP-2×R9700 MTP 91.4/73–81; each row's engine/quant/GPU stated in the page's own words |
| R15-S4 | docs.kernel.org/admin-guide/pm/amd-pstate.html (fetched) | EPP attribute semantics (lower=performance, default=firmware-set, dynamic mode), dynamic mode "while running under the powersave governor" + platform-profile registration — governor-name normality, EPP-is-the-lever, daemon-ownership mechanism |
| R15-S5 | wiki.archlinux.org/title/Power_management (fetched + search render) | EPP named-profile list (default/performance/balance_performance/balance_power/power); the ppd/tuned/tlp/cpupower competing-tool registry on rolling distros |
| (inherited) | R14-S1..S6, §D8/§D10/§D11, D44, §R8/§R9 power-tie falsification, [S2/S5/S7/S8/S12] | carried; nothing re-fetched contradicted |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R15 appended)]
commands_run: [repo reads (RQ1, §R8, §R13–§R14, §D6/§D8/§D10/§D11, D33–D44 incl. D44 retraction) => pass; codeberg raw fetches GUIDE.md @v1.17.0 ×2 (ngram/kv-resident/elastic/prefill sections) + flashnext-tp1.yaml + README model table => pass; llamaperf model page ×3 windows (full single-card census incl. RX9070/Strata row) + R9700 GPU page (carried) => pass; docs.kernel.org amd-pstate (EPP/dynamic/powersave texts) => pass; web_url_read ArchWiki Power_management ×3 windows (tool registry; ppd mapping not in fetched windows → UNVERIFIED); gitlab ppd README refused (sign-in wall) → labeled; searxng ×4 (one ERR batch, serialized around) => pass; arithmetic re-derived: 172 KiB/token & ≤4.2 ms wire ≤15% (launch's own numbers checked: 410673152/2385, 71.40GiB/2385, 7510 MiB/s, 28 ms base), QSA ≈6 KiB/token →9.3 GiB slab loss, TP2 ram fit ~83≤110, slab+950-units sensitivity => pass]
deviations: none — read-only, only RESEARCH.md written. The round's central answer is negative-as-instructed: the docs support no higher single-card iq4r decode and both speed-tier alternatives are priced out or capacity-spending — stated as the headline with the complete cross-engine table, and the coordinator's ≤15%-wire measurement was used (not overridden) as the premise for the inversion of §R14's motivation.
friction: the ppd→EPP exact mapping and cpupower save mechanics resisted clean fetch (gitlab sign-wall / man page not reached) — substituted a one-command ownership read rather than guessing; the 28–29 ms-MTP ambiguity could NOT be resolved from docs text and became the round's designated free probe instead of being argued; the QSA-drop slab cost used the doc's per-rank ring figure × our 1.6M tokens (labeled multiplication, not measured).
open_questions: [the best-tile + acceptance probe (one fixed run decides per-step vs per-token reading of the creator 28–29 ms AND which world our 35 lives in); which service owns EPP on this box (is-enabled read); whether the radiance image's gather is device-side for our card (assumed libr4d — cheap to confirm from a boot CONFIGURATION line)];
next_suggested: coord: (1) hand the owner the EPP-ownership read + `powerprofilesctl set performance` (or mask-then-persist) and re-run the §D8.3 fixed probe with the best-tile and `/metrics` acceptance counters — the ONLY remaining zero-cost decode experiment per this round; (2) fold the headline into DECISIONS at next touch — single-card iq4r ≈ the documented floor; 70+ is two-card territory — so the decode-improvement budget moves to the TP2 follow-up card, where flashnext.yaml's prefix-tier shape plus (for the first time) the ngram-ram tier are both affordable; (3) retire the tuning note's EPP-confused "fix the governor" wording per D36's re-pointing law (governor name is normal; EPP is the lever; cite R15-S4); (4) no session/ctx/placement changes — §R15-Q3 measured them sub-noise against the now-confirmed non-wire step.

---

## §R18 — hiding the 8060S APU: fact-check of the owner's guide, and what this cluster's own decisions change

Owner round 2026-11-15: fact-check the owner's note **"Hiding the Strix Halo APU
Graphics with One R9700"** against external sources and against what THIS cluster
already decided/measured (D21/B1, D24, §R6/§R7, §R9 APU verdict, TP2 §5/§6, tuning
note §12 "No hide experiments", §D46/D47 EPP+wire-zero results). The doc was written
against the PRE-C07 world (one `amd.com/gpu` pool, plugin `nodeId`-ascending picks,
no patched table) — most of its premises are history here. External cites R18-S#,
accessed 2026-11-15.

### R18 VERDICT (first)

**Don't hide.** The doc's *goal* — "no pod ever gets the wrong GPU" — is already
**fully closed on this box by the shipped scheduler lane** (first-party
`charts/amd-gpu` running v1.31.0.12 `-resource_naming_strategy=product` over the
D24 patched `amdgpu.ids`, node advertising `amd.com/gpu-r9700-1: 1` +
`amd.com/gpu-8060s: 1`, bare `amd.com/gpu` gone ⇒ a stray bare claim is
Pending-forever "loud by design", §R6-Q4/§D6), and its *side-effect* is the single
failure mode this ticket actually lived: stranding the `gpu-8060s` claim the llama-swap
router is scheduled from — i.e. **C10, 11 h 40 m, re-executed at the router's next
restart.** On the mechanics: the doc's RECOMMENDED route (vfio) is unavailable here
without reversing `amd_iommu=off` or enabling the kernel's self-described
*“unsafe DMA … w/o physical IOMMU protection”* noiommu knob [R18-S4] — declined; its
fallback (pci-stub/driver_override) works without IOMMU [R18-S5] but delivers ~0.5 GiB
RAM (we already print the APU at the `512.00 MiB VRAM` BIOS-minimum [R18-S7]) and zero
measured performance: §R9 found no attested idle-APU cost, §D46/D47 measured
**0.0 MiB/token wire during sustained decode** at 41.1/41.3 t/s — the APU is not where
anything is. Revisit only at the strata-cutover, if/when the owner intentionally kills
the APU serving lane (then hiding is tidy, cheap, and coherent) — procedure below.

### R18-CLAIM-TABLE (each: verdict for THIS box + citation)

| # | doc claim | verdict here | why |
|---|---|---|---|
| 1a | "the AMD device plugin advertises every GPU as `amd.com/gpu`; naming strategies only affect partitioned Instinct cards" | **WRONG-for-this-box** (was true pre-C07) | `.12` docs list product as a first-class strategy for any card: "`single`, `mixed` or `product`" [R18-S1]; §R6 source-verified `product` = per-marketing-name pools for consumer cards; our node advertises the named pools (live, §D6/§D8, final-review witnesses) |
| 1b | "device-count limits how many, not which" | **true-as-documented, dead-as-shipped** | docs: "Setting `AMD_GPU_DEVICE_COUNT` to a value lower than the physical count ensures only a subset of GPUs are made available" — subset identity unspecified [R18-S1]; §R6 proved the .12 binary implements neither it nor `CONFIG_FILE_PATH` (docs lead code; t1m.me class) |
| 1c | "`ROCR_VISIBLE_DEVICES` in a pod can't fix a mis-allocation" | **TRUE** | the plugin's `Allocate` returns only device nodes, "no env visibility" (S13; §R6-Q4): kubelet mounts what it allocated — env can re-order what /dev/kfd shows but cannot conjure the right render node; our own 2026-11-07 vllm crash is the index-order scar [S15] |
| 2 | "Strata PR #3636 measured 71–74 vs 46–49 decode; 2,530 vs 1,627 at 64K" | **TRUE but measures USE, not presence — and supports §R9, not the hide thesis** | the comparison is "the two ways to run the pair: **the 8060S + R9700 layer split**, and **the R9700 alone with the 8060S hidden and the whole expert arena in the Strix Halo's RAM**" [R18-S2] — a *split-serving* engine being kept OFF the APU beats *using* the APU; it says nothing about a visible-idle APU taxing a dGPU. (Its "71–74" is **Strata IQ3_S + RAM arena** on a Gen4-x4 box — another non-radiance, another-quant data point for §R15's census; radiance iq4r single-card still unshown >40, and our D47 41.1/41.3 now *beats* the creator's TP1 floor.) |
| 3 | "gfx11-before-gfx12 corruption (Strata #2706); device order not guaranteed across boots" | **TRUE of Strata in split mode; NEUTRALIZED for radiance here** | #2706 (closed): "STRATA_HC_UPMIX on a gfx11 + gfx12 layer split corrupts prefill on the gfx12 stage (gr_upmix caches its arch check from the first device)… Nothing crashes and nothing is logged" [R18-S3] — requires using both devices in one pipeline. radiance gets ONE render node (`Allocate` mounts `/dev/kfd` + `card1/renderD128`, S13/§R6): agent enumeration via kfd still *lists* the APU, but its render node isn't in the container, so compute on it fails at open (node-permission class, Unix-device mechanics + kubelet device-plugins doc R6-S16), and the engine prints exactly one: `1 device(s) [0:gfx1201]` (§D8.5); the GUIDE's own harness selects backends by env ("`ROCR_VISIBLE_DEVICES=99`" host-tier tests [R18-S8]) — radiance honors the standard env. Order-unstability is moot when the POOL is the identity: `gpu-r9700-1` claims can bucket only R9700 nodes (§R6-Q1 dpm per-name pools). |
| 4 | "iGPU unused → set BIOS carve-out minimum; ~123–125 GiB available; hiding + 0.5 GB frees it" | **true-in-general, INERT here** | we ALREADY print `512.00 MiB VRAM` for c5 (§D8.1) = the documented Linux minimum ("set the iGPU memory size (UMA frame buffer) to its 512 MB minimum in the BIOS" [R18-S7]); Strix Halo memory is dynamic GTT anyway (EVO-X3 twin: "only 1GiB visible VRAM, while AMDGPU exposes a 120GiB graphics translation table aperture", R9-S8 carried). Ram-tier arithmetic unchanged: gate needs `71.04 + 47.68 + 4 = 122.72` free under the cgroup vs pod **110** (or 114 with any hiding-gained +0.5 GiB — the doc's own RAM argument cannot reach 122.72), and node math caps any pod at ~119.8 (125.08 − 4.125 − 1.158, §R8/D6.2) ⇒ **ram-tier stays refused; verdict §R15-Q1 untouched by hiding.** |
| 5a | vfio bind (recommended) | **unavailable-as-recommended** | `amd_iommu=off` (deliberate, D28(5): "dma copy lists IN USE", NPU already sacrificed) ⇒ no IOMMU groups; vfio's escape is the knob the kernel itself labels "intended for usages where **unsafe DMA** can be performed by userspace drivers w/o physical IOMMU protection" (`enable_unsafe_noiommu_mode`) [R18-S4] — not a reasonable posture for this multi-tenant lab node; reversing `amd_iommu=off` contradicts our own working-path evidence (§R9/D28(5)). |
| 5b | pci-stub fallback (no IOMMU) | **mechanically viable** | per-function override is documented and IOMMU-free: `echo pci-stub > /sys/bus/pci/devices/0000:c5:00.0/driver_override` semantics per the ABI doc ("only a driver with a matching name will … bind … does not automatically unbind", April 2014 [R18-S5]); functions `1002:1586`+`1002:1640` [R18-S6/S17]. The USB-controller-in-the-group warning [R18-S6] is a **vfio-with-IOMMU** hazard and does not apply to per-function pci-stub — but nothing says so in the doc; standard-Linux-practice, flagged. |
| 5c | "plug a monitor into the R9700" | **irrelevant here (SSH-managed headless), true-in-general** | the APU's display outputs go dead; our access path is network+R9700 console — no cost, no risk, stated as the doc does. |
| 5d | hide → KFD/ttm/plugin/router effects | **THE cost** | c5 leaves amdgpu ⇒ leaves KFD and the plugin's `/sys/module/amdgpu/drivers/pci:amdgpu` walk ⇒ **`amd.com/gpu-8060s` disappears from node status** ⇒ the D21/B1 overlay claim `limits."amd.com/gpu-8060s": 1` strands at the router's next restart — **the exact C10/D26 11 h 40 m failure class** — plus the catalog's `-strix` fallback dies and the D24 APU-rows-carry ledger/test pins go stale (all of them code changes, not host-only). |
| 6 | goal-achieving alternatives | **all already shipped; nothing left to add** | per-product naming (C07/D24, live), explicit per-workload pools (radiance→`gpu-r9700-1`, router→`gpu-8060s`), stray-bare-claim=Pending guard ("loud by design", §R6-Q4-3), optional belt `HIP_VISIBLE_DEVICES=0` env on the radiance pod ("a belt to the suspenders … one values edit", §D8.5), k8s `ValidatingAdmissionPolicy`/CEL could force every GPU pod to name a pool (GA status UNVERIFIED this round — page fetch returned nav-only; mechanism itself documented at kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/); NFD/NodeFeatureRule unneeded (no NFD, §D11.2). |
| 7 | TP2: "nothing here changes" | **CONFIRMED (and hiding would only COST)** | TP2 §6: a second 7551/C0 "resolves to the same product name and **joins the same pool**: the node advertises `amd.com/gpu-r9700-1: 2`" — the doc's "worse with a second card" claim is bare-pool arithmetic from the world before C07; P2P stays the no-p2pdma host-mailbox lane regardless of the APU (§R11 carry); power-tie falsified by our 300 W print (D33); hiding the APU before TP2 would additionally delete the router's pool for zero TP2 benefit. |

### R18 — RECOMMENDATION + the if-ever procedure (for the strata-cutover lane only)

**Hide it: NO. Hide it later: ONLY as part of a deliberate APU-lane retirement**
(strata cutover Q5 lane), because at that point the router's `gpu-8060s` claim is being
removed by design anyway and hiding becomes free. The asymmetry is the whole story:
**mis-scheduling risk today = zero (pool identity), router-starvation risk if hidden =
one restart away, benefit = ~0.5 GiB and a measured 0.**

If ever executed, the procedure for THIS box (and its K8s-side consequence spelled
out — it is a D21/B1 REVERSAL, a code change in the same wave):
1. **Pre-flight reads (all read-only, all reversible by doing nothing):**
   `lspci -nn -d 1002:` (expect c5:00.0 `1002:1586` + c5:00.1 `1002:1640` + whatever
   else the SoC exports), `cat /sys/class/drm/card2/device/power/{control,runtime_status}`
   (expect `on`/`active`, §D8.1), router `/v1/models` (know the lane you're about to
   strand — §D8.5 witness: every model `unloaded` was this ticket's APU-cost null).
2. **CODE FIRST, same-wave law (D18 applied to host changes):** repoint
   `services/gpu-ai/prod/values.yaml` llama-swap overlay off `amd.com/gpu-8060s`
   (drop the GPU claim, or bare-if-on-bare-pool-node — it is NOT, so: no GPU),
   re-point the D24 ledger's APU rows/tests, retire the catalog `-strix` fallback,
   land + sync BEFORE any host bind, so the router is already GPU-free when the pool
   vanishes — the C10 lesson inverted.
3. **Host bind (pci-stub route; NOT vfio, see 5a):** `echo pci-stub > …c5:00.0/driver_override;
   echo 0000:c5:00.0 > /sys/bus/pci/drivers/amdgpu/unbind; echo 0000:c5:00.0 >
   /sys/bus/pci/drivers/pci-stub/bind` (same pair for `:00.1`), per the documented
   override semantics [R18-S5]; persist later via a modprobe/install-script step
   (kernel-parameter variant `pci-stub.ids=1002:1586,1002:1640` +
   `driver_override`-style early-bind ordering — bootargs edit, owner-lane).
4. **Rollback:** clear override + rebind `amdgpu` both functions (`echo > driver_override;
   echo …:00.0 > drivers/amdgpu/bind`), revert step 2 in GitOps. Verify: plugin reprints
   `Reporting 1 devices as amd.com/gpu-8060s` and node status regains the pool.
5. **Prints that prove each state:** node `.status.capacity` (`gpu-8060s` absent /
   present), plugin `-v=5` log device-map lines (§R6-Q4-5(b)), router pod Running with
   the new claim shape, radiance UNTOUCHED throughout (`gpu-r9700-1: 1` and its 41 t/s
   baseline, §D47) — and the runbook's `power cap` line re-read post-any-BIOS-change
   (Strix power-tie guard, D33).

### R18 — Conflicts / UNVERIFIED

- **Conflicts with our own record, resolved by precedence:** the doc re-opens exactly
  what D21/B1 (owner ruling) and TP2 §5 (this ticket's interdependency finding)
  CLOSED; the tuning note §12 already says "No hide experiments: `vfio-pci` on the APU
  would strand the router". Nothing here contradicts §R9's narrowed APU answer
  (idle-enumeration cost = zero attested; loaded-co-serving = open A/B question the
  doc's hide does NOT answer — if the APU is ever the co-serving suspect, the loaded
  router A/B (§R9 action) measures it in minutes, router alive).
- **Corrections carried:** PR #3636's 71–74 row joins §R15's census as another
  other-engine/other-quant single-card-class datapoint (Strata, IQ3_S, arena-in-RAM);
  it does NOT revive the 70+ expectation for radiance iq4r (our 41.1/41.3 stands as
  documented-floor-plus).
- **UNVERIFIED:** the owner's doc §5 exact wording (read second-hand via this launch);
  whether hiding the iGPU frees ANY further RAM on the Framework Desktop BIOS beyond the
  512 MiB already printed (no Framework BIOS menu doc found; the cfg "512 MB minimum"
  line is generic Strix-Halo advice [R18-S7]); ValidatingAdmissionPolicy GA version
  (nav-only fetch); behavior of `snd_hda`/audio function left bound while display is
  stubbed on this exact SoC (no Strix-Halo report found; the passthrough guide binds
  both [R18-S6]); whether a pci-stubbed c5 changes the engine's `not serving` HARDWARE
  block line count (cosmetic; the walk enumerates display devices); "device order not
  guaranteed across boots" as a general ROCm claim (our [S15] injury + index-order
  history is the evidence we have; no ROCm doc fetched asserting it).
- **Blunt note the doc makes itself:** every mechanic it cites is standard Linux PCI
  practice (vfio/pci-stub/console/BIOS carve) — and standard practice meets THIS box at
  three points: no IOMMU (vfio arm dead), the router schedules BY THE APU POOL NAME
  (hide arm costs the router), and the pools already name-identify the cards (goal
  arm moot).

### R18 — Sources (accessed 2026-11-15)

| # | URL | What it is |
|---|---|---|
| R18-S1 | raw.githubusercontent.com/ROCm/k8s-device-plugin/v1.31.0.12/docs/user-guide/configuration.md (fetched) | Flag table incl. "`single`, `mixed` or `product`"; `AMD_GPU_DEVICE_COUNT` section + "ensures only a subset of GPUs are made available" (no which-subset control); CONFIG_FILE_PATH YAML example (docs-side existence; binary doesn't implement either — §R6) |
| R18-S2 | github.com/Niko1221/Strata pull/3636 via api.github.com (fetched) | The Strix-Halo+R9700 benchmark PR: "the two ways to run the pair, measured with fresh engines: the 8060S + R9700 layer split, and the R9700 alone with the 8060S hidden and the whole expert arena in the Strix Halo's RAM"; "the R9700 alone beats the split: 64K prompt 1,627 -> 2,530 tok/s, 200K first token 141 s -> 87 s, decode at depth 46-49 -> 71-74"; "decode (82.9 vs 48.1 tok/s)"; IQ3_S quant, "OCuLink PCIe 4.0 x4" |
| R18-S3 | github.com/Niko1221/Strata issue/2706 via api.github.com (fetched; state=closed) | The gfx11→gfx12 upmix corruption, in Strata's split path: "caches its arch check from the first device … Nothing crashes and nothing is logged" + rel-RMS table (1e-7 on gfx1151 stages vs 0.43–0.70 on gfx1201 stages) |
| R18-S4 | raw.githubusercontent.com/torvalds/linux/master/Documentation/driver-api/vfio.rst (fetched) | "VFIO also supports a no-IOMMU mode, intended for usages where unsafe DMA can be performed by userspace drivers w/o physical IOMMU protection. This mode is controlled by the parameter: /sys/module/vfio/parameters/enable_unsafe_noiommu_mode" + the capability-matrix table |
| R18-S5 | raw.githubusercontent.com/torvalds/linux/master/Documentation/ABI/testing/sysfs-bus-pci (fetched) | `driver_override` ABI (April 2014): per-device driver pinning incl. stub drivers, "does not automatically unbind … may be cleared with an empty string" — the IOMMU-free reversible route |
| R18-S6 | strixhalo.wiki/Guides/VM_iGPU_Passthrough (raw-backed fetch) | The iGPU function set `1002:1586,1002:1640` + `disable_vga=1`; "the last one is a USB controller" in the passthrough set; the "reset bug … only once per boot of the host" (VM-passthrough context); blacklists for host-off |
| R18-S7 | computingforgeeks.com best-oculink guide (fetched in §R14, carried) + jdhodges.com Strix-Halo VGM guide (search render) | "On a Strix Halo Linux box, first set the iGPU memory size (UMA frame buffer) to its 512 MB minimum in the BIOS. Leaving the 96 GB carve-out in place … starves the operating system"; VGM = Adrenalin/BIOS carve semantics |
| (internal) | §R6/§R7 (naming+constants), D21/B1+C10/D26 (router starvation), D24 (patched table), §D8.5/§D10/§D11 (APU prints), §D46/D47 (EPP + wire 0.0), TP2 §5/§6, tuning §12, [S13/S15/S16/S18] | the ticket's settled record this fact-check adjudicates against |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R18 appended)]
commands_run: [repo reads (owner-doc traces via grep: TP2 §5 verbatim, tuning note §12 "No hide experiments", STATE R9 summary; D45/D46/D47 full text; §R6/§R7/§R9/§R11/§R15 re-read) => pass; api.github.com fetches: Strata pull/3636 (numbers + split-vs-hidden framing) and issue/2706 (corruption mechanism, closed) => pass; raw fetches: ROCm device-plugin configuration.md @v1.31.0.12 (naming/count/config-file doc lines), torvalds vfio.rst (noiommu "unsafe DMA" text), sysfs-bus-pci (driver_override ABI), radiance GUIDE @v1.17.0 (ROCR_VISIBLE_DEVICES=99 harness line; no --device flag) => pass; strixhalo.wiki VM_iGPU_Passthrough via reader (ids/USB-controller/reset-bug), VGM/cfg quotes via search renders => pass; k8s VAP page nav-only (GA claim marked UNVERIFIED); ram arithmetic (122.72 vs 110/114; 0.5 GiB already-minimum) re-derived => pass]
deviations: none — read-only; RESEARCH.md only. The doc's headline evidence (PR #3636) was checked and it cuts against the hide thesis here: it measures USE-of-APU-split vs USE-of-RAM-arena with the APU hidden — a Strata split-mode result, not a presence-tax result; stated with its own words. The verdict is also blunt in the doc's favor where it's right (1c, the goal, the general Linux mechanics) and blunt against it where this box differs (vfio arm dead on iommu-off; goal already closed; hide costs the router pool).
friction: the owner's document file itself was not in-repo (searched notes+plan folders) — fact-checked claim-by-claim from the launch's verbatim quotes and labeled as such; the VAP reference page resisted the reader (nav-only) — mechanism cited, version claim left UNVERIFIED; no source exists for "audio function left bound while display stubbed" on this SoC — flagged rather than extrapolated from desktop-GPU practice.
open_questions: [whether the strata cutover (Q5 lane) retires the APU serving class at all — that, not mis-scheduling fear, is the only future trigger for hiding; any Framework Desktop BIOS menu documentation for the UMA carve (would upgrade the "already at minimum" from our engine print to doc-confirmed); audio-function co-binding behavior on stub (no report found)]
next_suggested: coord reply to the owner's doc with the table: keep it as the cutover-day runbook (its §5 mechanics are fine, its §1 premises are pre-C07), record R18 in the next DECISIONS fold as "hiding: no — goal closed by shipped naming, sole cost = router starvation (C10 class), revisit only inside the strata-cutover APU-lane retirement (procedure §R18: code first, pci-stub per-function, rollback = rebind+revert)", and spend nothing: the measured ~41 t/s on a confirmed Gen4/wire-zero box is where the compute floor is; the 70+ class is TP2's documented lane (62–65 docs-measured, 137 L1T), already carded as AD-144.

---

## §R16 — the knobs the live /diagnostics dump exposed: `--expert-pin-top`, prefill fp8, the n-gram drafters, and what each costs

Owner round 2026-11-15. Ticket state carried WITHOUT re-argument: one R9700, 110/110
Guaranteed, Gen4 x4 stable (D44/D50), **wire 0.0 MiB/token sustained decode** (D47),
~41 t/s sustained (D47's 41.1/41.3), 8×200K envelope is the owner's binding constraint
(Q10/D17 — knobs that spend sessions/context are not free), §R15's census (no published
single-card iq4r >~40; TP2 is the 70+ lane), §R18/D49 (no APU hiding). Doc citations
R16-S1/S2/S3 = GUIDE.md / spec.md / TOOLS.md **@v1.17.0**, codeberg api raw, fetched
2026-11-15. The /diagnostics dump quoted in the launch is this section's configuration
of record.

### R16 VERDICT (first)

**The flagship knob is undocumented: `--expert-pin-top`, `--expert-profile` and
`--draft-expert-placement` appear in the live dump but in NO v1.17.0 doc we could
search — exact strings `expert-pin-top`/`pin-top`/`expert-profile`/`draft-expert`
return nothing in GUIDE.md, TOOLS.md or spec.md [R16-S1/S2/S3].** (The only "pin" hits
are vision-tower pinning and a quantiser bias note; spec.md §5.3's documented
mechanism is the container's **imatrix popularity profile** + heat re-rank: "The
container's expert-popularity profile, derived from the imatrix's activation counts,
ranks which experts begin resident. It is only a starting point… the heat engine
re-ranks within a few steps" [R16-S2].) So the dump's `--expert-pin-top 0` is a
**code-leads-docs** situation (§R6's mirror image): the flag's semantics, its
interaction with the lending-cache split (`experts 17.76 / kv 4.51 / staging 1.63`)
and any affordable value at 8×200K are **UNVERIFIED — we will not propose a number we
cannot source**. What the docs DO support, and it is not nothing: the `--expert-stats`
**measurement** ("count the routed experts every layer selects, apart for prefill,
decode, mixed steps and draft-head passes… Counted on the host from the routing
histograms the core already copies back for the heat engine, so it adds no device
work and no synchronisation" [R16-S3]) — the free way to learn our hot-set shape
before touching any pin. Beyond that: **every documented, envelope-preserving knob in
the dump is already at its docs-recommended value (Q4), the n-gram-disk theory was
WRONG ABOUT THE MECHANISM but is still ALIVE** (the table is read per-token by the
model's PLE lookup, not by the drafter — `--spec-ngram 0` doesn't silence it), the
12288 question RESOLVES in favor of checkpoint/chunk-granularity (D47's hypothesis
confirmed with docs, §R15's "no hits at all while streaming" reading corrected), and
**nothing on one card credibly reaches 70: the honest budget stays AD-144/TP2**
(62.3–64.8 docs / 137 L1T), with the pin-top experiment as a zero-envelope-cost
maybe-if-undocumented pilot at single-digit expected gain.

### R16-Q1 — `--expert-pin-top` (+ `--expert-stats` / `--expert-profile`)

- **Doc status: UNDOCUMENTED at the pinned release** — searched exact + loose tokens in
  all three docs; zero hits [R16-S1/S2/S3]. The dump prints the flag with `source`
  default ⇒ the 1.17.0 binary accepts it; no formula, no per-layer-vs-global
  semantics, no "hot" definition, no stats/profile dependency, no magnitude guidance
  is stated anywhere we can cite. **Say so plainly: any pin value we'd pick is
  guesswork, and the docs themselves forbid guessing this one's interaction — the
  lending-cache law is engine-derived: "the engine derives the split… no flag states
  either pool" [R16-S1 §4.3], and pinning is a placement override into exactly that
  derived split.**
- What the docs DO establish about the residency substrate a pin would spend:
  elastic 23.89 GiB = experts 17.76 + KV 4.51 + staging 1.63 + slack (~2.4 incl.
  `unclaimed 94.83 MiB` + the "1.23 GiB lent … while no request holds it" KV-side);
  slab = 7,520 units @ 2.42 MiB [§D8.2]; "The cache never gets less than one
  `--max-model-len` sequence" [R16-S1] — at 8×200K the cache-addressable is already at
  its `max-seqs×max-model-len` bound and holds it (boot claim "backs 8 sequences all at
  200000" [§D8.1]) ⇒ **any pinned VRAM must come out of the 1.23 GiB loaned slack plus
  staging headroom — arithmetic ≈ ≤300–500 units (≤12% slab) before the KV guarantee
  or the 96 MiB kernel-launch headroom is threatened.** If pin-top spends per-LAYER
  units, max-300 resident rows mean it may be partly redundant with heat (which
  already holds the hot set); if it spends a GLOBAL set, it can beat heat's hysteresis
  — **which of these it is = UNVERIFIED, decide only after `--expert-stats` data.**
- **Does the stream shrink if pinning works?** The doc's own law: "decode touches a
  few experts per layer per token and residency decides its speed" (spec §5.3
  [R16-S2]) — so yes directionally; magnitude bounded by the ≤15% wire share (D47):
  even a perfect pin cuts only the ~4.2 ms/token mover upper-bound term ⇒
  **best-case single-digit-percent decode at ~41 t/s. Not the 70 answer. No capability
  spend if affordable — that's the one honest upside.**
- **Measurement plan instead of a formula** (all free, envelope-intact):
  1. enable `--expert-stats <path>` IF accepted as a server flag (the TOOLS.md entry is
     inside a tool's flag table — attribution to the server binary itself is
     UNVERIFIED; the /diagnostics dump's own `--expert-stats off` line proves the
     server knows the name); collect ≥30 s JSON (writes "every 30 s and at shutdown",
     per-tool doc line [R16-S3]);
  2. compute the decode-time hot set: for each candidate pin size, share of DECODE
     visits covered; if top-N (N ≈ 300–500 units globally) covers <80%, do not pin;
  3. trial the flag at the affordable N, A/B with the §D8.3 fixed probe ×2 + the D47
     counters (Δ`pinned`/`memory.peak` under the cgroup reads, request-`done` t/s,
     `/diagnostics` `expert prefetch` + mover lines); keep only if ≥+3% sustained with
     `pinned` NOT rising past the 71.04-class ceiling;
  4. read `16 GT/s` link line + `oom_kill 0` each arm (regression tripwires).

### R16-Q2 — Residency-adjacent knobs: what's actually free

| knob (dump value) | doc meaning | decode effect / cost |
|---|---|---|
| `--weights-disk-tier off` | "experts that fit neither VRAM nor pool stream from the container via 4×32 MiB pinned windows… meant for running a checkpoint as shipped, to calibrate or compare" + "Without the flag, a budget that does not fit is refused at startup" [R16-S1 §4.3] | off is right: on = file-IO in the stream path; a RELIEF VALVE not a speed knob |
| `--host-headroom-mib 4096` | the placement-spare the ram tiers keep out [R16-S1] | lowering to 2048 does NOT unlock ngram-ram: 110 − 71.04 = 38.96 < 47.68 + 2 anyway; don't bother |
| `--checkpoint-interval 4096` / `--checkpoint-slots 72` / `geometric-backoff` | checkpoint = linear-state snapshots "always live in host pinned memory" [RQ1/S2 §4.8] + dump's own slot arithmetic ("9 a sequence… one more for a running turn") | **host RAM, not VRAM** — no expert-slab gain available from touching them; slots × ~113.5 MiB ≈ 8.2 GiB of the 45 GiB free — leave |
| `--weight-prefetch on` | the next-layer DMA prefetch; §8 only says turn it `off` for a SECOND co-resident engine [R16-S1] | on is the single-engine optimum |
| `--control-vector` disabled | optional per-request steering gguf; absent file ⇒ inert [R16-S1 §4.x: "Without it nothing is read… /admin/control-vector answers 404"] | neutral; leave |
| `--draft-expert-placement auto` | **undocumented at 1.17.0** (zero hits [R16-S1/S2/S3]) | semantics UNVERIFIED; leave `auto` |
| elastic loan | docs: cache "lends every block no live request holds back to the expert slab in place" [R16-S1] | already automatic — heat+loans ARE the pin mechanism the docs endorse; our 46.2% prefetch-usage is the documented TP1 norm (§R15-Q2) |

### R16-Q3 — Prefill/TTFT knobs

- **`--attn-prefill-fp8 off`**: docs give the gate exactly — "libr4d has the kernels
  for **Qwen3.8-27B's** attention (head_dim 256, gqa 6, 16-token pages); anywhere no
  kernel takes the flag (another geometry, a `bf16` cache, the host backend) **startup
  stops, naming it**" [R16-S1]. Flash-Next's geometry is NOT among the named kernels
  ⇒ for our model expect a startup refusal; UNVERIFIED only in the pedantic sense.
  Not a lever here.
- **`--state-cache-dtype f32`**: "The `qwen35` plugins… declare the recurrent state
  cache f32. With `--state-cache-dtype f16` they declare it f16… a plugin that does not
  serve it is refused at startup by name. It is lossy" [R16-S1] — qwen4exp not listed
  ⇒ refused-or-untested for fn; and the halved-state gain "grows with the number of
  decoding sequences" targets multi-seq state traffic, not our case. Leave.
- **Chunk geometry — DO NOT RAISE `--max-num-batched-tokens` past 4096** and the docs
  quantify why: "The checkpoint interval caps the chunk… asking for 4096 runs
  2048-token chunks with an activation arena sized for 4096, and **the expert plane
  loses residency for a chunk it never gets**"; "Raising both (4096/4096)… 2610 tok/s
  against 2748, **because the arena took another 239 resident experts (9219 to
  8980)**" [R16-S1 §4.5]. Our 4096/4096 is the creator-profile choice (flashnext-tp1
  yaml, §R15-S2) — the docs' own table shows 2048 slightly BEATS 4096 for prompts
  alone (2706 vs 2620) but 4096 wins the 185K-prompt wall class and the amortization
  argument in the compose header. **Leave at 4096; raising breaks residency twice.**
- **`--busy-prefill-chunk auto` + `--prefill-interleave off`**: auto's full paragraph
  (share-per-row, "a long prompt (a minute or more at 256K) does not starve decode rows
  or admission", floor at the stager's overlap minimum) [R16-S1] — auto is the docs'
  designed state; `--prefill-interleave` trades TTFT FOR cadence ("the prompt's time to
  first token grows by those steps" — wrong direction for our TTFT pain). Leave both.
- **The prefix-cache "contradiction" RECONCILED, and D47's 12288 RESOLVED**:
  `--prefix-cache-mib 0` = the **host tier** size; `--no-prefix-cache` (not given) =
  on-card prefix retention ON ("prefix hits still work from VRAM" while streaming
  [R16-S1 §4.4.1]; the dashboard's "dim segment is prefix cache, finished turns kept
  for reuse, which gives way the moment a live request needs it" [R14-S1 §6.1]). So
  the dump's `prefix caching on` + `tier 0` is consistent — and **§R15's claim that
  streaming force-disables prefix reuse wholesale is CORRECTED: it suppresses the host
  tier only** (D47(2b) predicted exactly this; docs side with it).
  **`cache 12288` is not a KV block size** (blocks are 4-token, "4 tokens on this
  family" [R16-S1]): `--prefix-resume exact` hits "resume only where an idle server's
  cold prefill… starts a chunk: every `--max-num-batched-tokens` tokens (rounded down
  to the chunk quantum), or every `--checkpoint-interval` when that is smaller"
  [R16-S1] ⇒ hit depths quantize to 4096-boundaries — **12288 = 3×4096 exactly**. The
  TTFT collapse 25.44→6.27 s at prompt≈14.2k with 12288 cached is the docs' designed
  behavior of a 3-chunk resume.
- **Docs-recommended TTFT cut without touching 8×200K:** the chunk/checkpoint pair we
  already set (4096/4096 IS the 2× speed-vs-residency sweet spot the §4.5 table
  computes), plus prefix resumes happening on their own (agent turns re-prefill only
  "the cold run's last chunk + what the turn added"). No further flag buys TTFT for
  cold prompts on this geometry; 4096-chunked prefill at ~551 tok/s (D47) is inside
  the doc's link-amortization story.

### R16-Q4 — What is already optimal (do not fight the `auto`/`from the container` rows)

Leave alone, each because the docs chose it as a resolution: `--tp-wire exact` +
`--tp-wire-min-kb 128` + `--p2p n/a` (single rank: "one rank: no collective crosses a
card"), `--weight-prefetch on`, `--busy-prefill-chunk auto`, `--prefill-interleave
off`, `--preempt-wait-ms 5000`, `--prefix-resume exact`, checkpoint trio (Q2),
`--embedding-placement ram` and `--vision-tower-placement vram` (the auto block:
"startup prints what each table resolved to and why" — these ARE the resolved-best
placements for our caps [R16-S1 §4.3]), kernel selection (`libr4d 3107 bands / libavx
2980 host`), sampling `temp 1 / top-k 20 / top-p 0.95` **from the container** (the
pack's own guidance — the runbook's Q8/smoke chain), `--draft-model` head-not-in-pack
(the pack carries MTP — RQ0), `--http-threads 32` ("one a hardware thread"),
`--max-n 8 / --max-queued-requests 64`, `--deterministic off` (would freeze the heat
engine — the one flag that WOULD hurt: "under deterministic step() proposes nothing for
the whole run" [§D8.2b carry]), and `--spec-ngram`'s default off being the
**drafter** switch, not the table. The `unclaimed 94.83 MiB` + `card settled at
220.80 MiB free` lines say the VRAM plan is tight-and-correct; the only live anomaly
to watch is bookkeeping, not placement: **runtime `pinned_bytes 76.28 GiB` vs startup
`71.04` vs cgroup `memory.peak 72.4`** — three instruments, three scopes (mlock-set vs
cgroup RSS vs per-counter) and the ordering (76.28 > 72.4) says at least one counts
something the others don't (driver-locked pages? shared mappings double-counted?) —
**UNVERIFIED; one owner read (`cat /proc/<pid>/status | grep VmLck` +
`memory.current`) next time radiance idles settles it. Flagged, not guessed.**

### R16-Q5 — The 70+ question, ranked, with the envelope kept or spent per row

| rank | action | expected decode Δ | envelope cost | externally backed? | A/B print |
|---|---|---|---|---|---|
| 1 | `--expert-stats` data-capture pass, then **only-if**-informed `--expert-pin-top` pilot | 0 to +3–5% (wire share ≤15% caps the prize) | **none** (if affordable in the ~300–500-unit slack) | HALF: substrate documented (spec §5.3–5.4), the pin flag NOT (UNVERIFIED) | fixed probe ×2 + Δprefetch/mover lines + `pinned`/VmLck not rising |
| 2 | Nothing else on this box — every other dump knob is at its documented optimum (Q4) | — | — | — | — |
| 3 | **AD-144 TP2** (second R9700): pool 2×12288, prefix tier back (creator's flashnext.yaml shape), ngram **ram tier finally fits** (~24+4+1.2+47.68+4 ≈ 81 GiB ≤ 110 → "a step has no host work"), wire halves per rank | **the docs' own measured band: 62.3–64.8 with MTP @62K** [R14-S2]; L1T sustained **137** [R14-S1]; Strata's hidden-APU row (71–74) is the same physical story | costs a card, not the envelope (host math fits: §R8-Q5; D29's strata inversion stands) | YES (three independent receipts) | same fixed probe + 140–160-class prefill row check |
| 4 | (rejected rows, named so we stop revisiting) ctx↓ / seqs↓ (envelope-spending, Q10/D17), attn-prefill-fp8 & state f16 (fn geometry: startup-stops or refused-by-absence [R16-S1]), batched>4096 (loses residency twice [R16-S1 §4.5]), weights-disk-tier on (relief valve), APU hiding (§R18/D49), ngram-ram at TP1 (gate: 38.96 < 51.68 [§R15]) | — | — | — | — |

**Plain verdict: nothing on one card credibly reaches 70 — the ceiling is ~41 with at
most single-digit percent of documented-headroom left, so every row above except TP2 is
hygiene.** AD-144 is the 70+ purchase with three doc-adjacent receipts; row 1 is the
free lottery ticket worth exactly one stats-capture afternoon.

### R16 — Conflicts / corrections / UNVERIFIED

- **Corrects §R15's own text (loud):** "`--kv-resident` force-disables the prefix
  tier" ⇒ precise version: force-disables the **host** tier; on-card prefix hits live
  (they're where `cache 12288` came from). §R15's cliff-quote stays valid; its blanket
  does not. (D47 flagged it; docs confirm.)
- **Resolves the coordinator's n-gram theory both ways:** `--spec-ngram` = prompt-lookup
  DRAFTER switch (per-sequence index, "8 bytes a token per pattern length, 16 MiB at
  400k tokens" [R16-S1]) — NOT the container's 47.7 GiB PLE/n-gram table, which "is read
  a few rows a token" with "about half of a step's rows first-seen, so steps wait on the
  drive" under `disk` [R16-S1 §4.3]. So `spec-ngram 0` does NOT silence the table; the
  disk-wait suspect **stays alive** — but D47's 0.0 MiB/token KV-stream counter and the
  mover upper bound do not cover it (it's storage-side host work, not link bytes), and
  it remains the largest uninstrumented term of the ~24 ms. AD-145 (XFS move) would
  only normalize the ENGINE'S CHOSEN 4096-byte span policy (span = fs block size,
  reads still direct) — **expected small, unchanged priority (third-order, §R15-Q4
  rank 3; the ram tier, which kills the waits outright, remains TP1-locked)**. spec.md's
  mover note ("every slot and sub-region is a multiple of the logical block size
  O_DIRECT requires") describes the WEIGHTS file tier — not evidence the ngram row-cache
  spans change on ext4: marked UNVERIFIED.
- **UNVERIFIED list:** `--expert-pin-top`/`--expert-profile`/`--draft-expert-placement`
  semantics entirely (undocumented at 1.17.0; binary accepts the names); whether
  `--expert-stats` is server- or tool-scoped (TOOLS.md table attribution); the
  pinned-bytes discrepancy (VmLck read pending); flash-next acceptance of
  attn-prefill-fp8/state-f16 (docs name only other plugins' kernels — "startup stops,
  naming it" is the stated failure mode, not tested here); 2048-vs-4096 at OUR agent
  workload mix (docs' table is 27B/TP2); the top-N-coverage shape of decode routing
  until the stats file exists.
- **Carried, unmoved:** §R15 census/ceiling, D47 wire-zero, D44/D49/D50 link+hide
  rulings, §R8 capacity law, Q10/D17 envelope.

### R16 — Sources (accessed 2026-11-15)

| # | URL | What it is |
|---|---|---|
| R16-S1 | codeberg.org/api/v1/repos/StillDeadcode/radiance/raw/docs/GUIDE.md?ref=v1.17.0 (fetched, 14 targeted windows) | Authoritative flag semantics: §4.3 split/lending/headroom/lookup-tables (ngram "read a few rows a token", disk wait, ram gate, ram=DIR) + weights-disk-tier + expert-prefetch-usage; §4.4.1 streaming cost model + host-tier-off-while-streaming + "hits still work from VRAM"; §4.5 chunk table (1750/2200/2706/2620; 91 s at 2048; checkpoint-caps-chunk + "arena took another 239 resident experts"; interleave/prefill-span/busy-prefill-chunk full text; prefix-resume exact boundaries); §4.6 spec-ngram prompt-lookup (per-seq index bytes; verify-row economics; draft-window); state-f16 + attn-prefill-fp8 kernel-gate texts; control-vector block; §6.1 dashboard segments |
| R16-S2 | codeberg.org/.../raw/spec.md?ref=v1.17.0 (fetched, windows) | §5.3/§5.4 planner laws: "decode touches a few experts per layer per token and residency decides its speed"; warm start from container imatrix profile; mover/heat file-tier O_DIRECT design; placement-miss classes |
| R16-S3 | codeberg.org/.../raw/docs/TOOLS.md?ref=v1.17.0 (fetched) | `--expert-stats FILE` semantics ("apart for prefill, decode, mixed steps and draft-head passes… adds no device work and no synchronisation") in its tool's flag table (server-vs-tool attribution flagged); confirms NO pin-top/profile/draft-expert entries in tool docs either |
| (internal) | live /diagnostics dump (launch, 2026-11-15), §R14-S1/S2, §R15-S1/S2, D44–D50 | configuration of record + prior findings corrected where stated |

RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md (§R16 appended)]
commands_run: [codeberg api-v1 raw fetches: GUIDE.md @v1.17.0 (×3 calls, ~14 keyword windows — pin/profile/draft-expert NEGATIVE results verified across exact+loose tokens; ngram/prefix-resume/checkpoint-caps/state-f16/attn-fp8/busy-prefill texts captured), spec.md (planner laws, warm-start, mover file-tier), TOOLS.md (expert-stats entry + tool-table attribution check) => pass; repo state reads (§R15 verdict, D44–D50 summaries per launch, dump-vs-startup figures cross-checked: 76.28/72.4/71.04 discrepancy flagged not resolved) => pass; arithmetic: 4096-boundary 12288 fit; ram-gate 38.96<51.68 recheck; affordable-slack ~300–500 units; wire-share ceiling 0.15×41→≤+3–5%; TP2 host fit ~81≤110 => pass; web searches this round: none needed beyond doc raws (the round's claims were all engine-doc-internal)]
deviations: none — read-only; only RESEARCH.md written. The round's instruction "if the docs don't say, SAY SO" was exercised at full length: pin-top/profile/draft-expert declared undocumented with the negative-search method stated, and NO value was invented. Two internal corrections issued rather than smoothed: §R15's blanket prefix claim (host-tier only) and the coordinator's spec-ngram conflation (drafter ≠ PLE table — the disk-wait suspect survives, at documented 3–10% priority).
friction: the GUIDE's flag table's exact-string search for --expert-pin-top returning nothing required a triple re-check (pin-top/--expert-pin/'pin ' + spec.md + TOOLS.md) before declaring undocumented — cheap insurance against a false negative; the 76.28-vs-72.4 pinned/peak ordering is a genuine instrumentation contradiction whose resolution needs one VmLck read we are not permitted to take — logged as the round's flagged-UNVERIFIED rather than reconciled by assumption.
open_questions: [the stats-capture pass' hot-set shape (decides whether a pin pilot is worth running at all), expert-pin-top's per-layer-vs-global semantics (undocumented — decide empirically or ask upstream on Codeberg), VmLck/memory.current live reconciliation, whether 2048-vs-4096 flips at the owner's actual agent mix (docs' table isn't ours)]
next_suggested: coord: (1) offer the owner exactly two actions — a free `--expert-stats` capture afternoon + optional informed pin pilot (row 1, zero envelope cost, ≤+3–5% honest cap), and AD-144/TP2 as the only 70+ road with receipts; (2) fold the two corrections (§R15 blanket → host-tier-only; drafter ≠ PLE table) into the next DECISIONS round and the D47(2b) open item, which this round closes with docs; (3) put the VmLck/peak reconciliation on the runbook's next-touch list; (4) record that nothing else in the dump should be edited — the `auto`/`from the container` block is the engine's own optimum and the docs say why (Q4).
