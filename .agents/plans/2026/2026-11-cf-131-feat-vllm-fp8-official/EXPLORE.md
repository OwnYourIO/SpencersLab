# EXPLORE — cf-131 "vLLM: drop GGUF, serve official FP8"

Grounded by `agent-explore` 2026-11-07, read-only (repo reads + read-only MCP
probes on `readonly-ai-gpu-kubernetes`, `dev-boards` + live HuggingFace API
fetches of the pinned checkpoint). Worktree
`cf-131-feat-vllm-fp8-official` @ 5ddcf3997 (main tip; cf-123 work merged).
The owner-pivot record commit `42c55b4bc` lives on the owner's
`fix-vllm-common-loader` branch (2-line DECISIONS append only — NOT in this
branch's history; no code surface to chase).

The request (WeKan AI-Dev card #131, id `unDxRqcrNTfahp656`, board
`TNQJ2BrXenZovngTS`): drop the GGUF path and serve
`Qwen/Qwen3.8-27B-FP8` (official, stock-loadable), KV q4 default / q8 toggle
(values key), keep vision (no `--language-model-only`), keep "1m heads"
(interpretation open — §5). Successor to cf-105; the priority wiring landed by
cf-105 + cf-105-vllm-followup is live on main and must be preserved (§4).

---

## 1. Live cluster state (probed 2026-11-07 ~21:30 UTC, `readonly-ai-gpu-kubernetes`)

**Cluster/node.** `ai-gpu` — k3s `v1.36.5+k3s1`, single-node
(`node-role.kubernetes.io/control-plane: true`), 32 CPU, 131151324Ki (~125 GiB
usable — the RAM-law constant, cf-105 EXPLORE §8.6), `amd.com/gpu: 2`
(R9700 gfx1201 + 8060S gfx1151). Chip map (owner-verified on target, card
backlinks): KFD node1 = R9700 (gpu_id 0x59838, renderD128, PCI c4:00.0),
node2 = 8060S (0x53221, renderD129, c5:00.0); `ROCR_VISIBLE_DEVICES=0` =
R9700. The amd-gpu device plugin is blind on this node (coin-flip allocation —
the 2026-11-07 crash) — the pod must NOT use `amd.com/gpu` requests; this is
pinned by test (`test_ac2_gpu_ram_shm_pod_shape` asserts its absence).

**The vLLM pod is UP and SERVING today** (first healthy engine on the R9700 —
the runAsUser-0 fix of commit `48085beee`, owner-merged 2026-11-07):
- `gpu-ai-vllm-7f95cbbf6c-pt7bk`, ns `default`, node `ai-gpu`, Running 1/1,
  1 restart, startTime `2026-11-07T20:05:09Z`; pod annotation
  `kubectl.kubernetes.io/restartedAt: 2026-11-07T11:10:00-07:00`
  (operator restart trigger).
- Engine log: APIServer ready `20:19:25` (~14.3 min pod-start → ready on the
  first run; `init engine (profile, create kv cache, warmup)` 23.25 s).
- **Live container spec** (from `pods_get`; identical to chart values today):
  - image `ghcr.io/ownyourio/vllm-rocm:main` (the GGUF-plugin overlay,
    `pullPolicy: Always`, PIN-ME)
  - args (verbatim, D4 recipe): `--model /models/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q4_K_XL.gguf --served-model-name qwen3.8-27b-vllm --scheduling-policy priority --max-model-len 262144 --max-num-seqs 4 --kv-cache-dtype fp8 --gpu-memory-utilization 0.95 --enable-prefix-caching --language-model-only --enforce-eager --watermark 0.05 --enable-sleep-mode --disable-access-log-for-endpoints /health,/metrics,/ping`
  - env: `ROCR_VISIBLE_DEVICES=0`, `TRITON_CACHE_DIR=/data/triton`,
    `HUGGINGFACE_HUB_CACHE=/data/hf`, `VLLM_SERVER_DEV_MODE=1`
  - resources: requests cpu 4 / mem 16Gi, limit mem 32Gi (no amd.com/gpu)
  - securityContext: `privileged: true`, `seccompProfile: Unconfined`,
    `runAsUser: 0`, `runAsGroup: 44`, `capabilities.add: [SYS_PTRACE]`,
    hostIPC: true — the proven shape (GID-486 root cause; do not return to
    non-root without a host udev fix, card backlinks + followup DECISIONS)
  - volumes/mounts: `cache`=pvc `vllm-cache` → `/data`; `models`=pvc
    `llama-swap` (readOnly) → `/models`; `kfd`=hostPath `/dev/kfd`
    (CharDevice); `dri`=hostPath `/dev/dri` (Directory); `shm`=emptyDir
    Memory 8Gi → `/dev/shm`
  - probes: startup httpGet `/health:8000` 60 s + 10 s × 90; liveness +
    readiness `/health:8000`
  - annotations: exactly two `k8s.grafana.com/*` (scrape true,
    portNumber 8000)
- **Service** `gpu-ai-vllm` (ClusterIP 10.43.57.148:8000, created
  2026-11-07T00:01:40Z) — the peers.vllm hop target. ArgoCD tracking id
  `gpu-ai-vllm:/Service:default/gpu-ai-vllm` (release `gpu-ai-vllm`, appset
  `gpu-ai-appset`).

**PVCs (default ns, both local-path, both RWO, both Bound):**
- `llama-swap` 500Gi (28 d old; volume pvc-e4f5adf3-…) — the shared weights
  claim; llama.cpp cache root `LLAMA_CACHE=/models`, no `hub/` segment. The
  Q4 GGUF `Qwen3.8-27B-UD-Q4_K_XL.gguf` (16.35 GiB) is under
  `/models/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca72078…/` (live,
  pinned by the dual modelPath).
- `vllm-cache` 10Gi (21 h old — created today when the chart's hand-written
  PVC template first applied; volume pvc-f986a778-…) — `/data` with
  `TRITON_CACHE_DIR` + `HUGGINGFACE_HUB_CACHE`. **28.77 GiB of FP8 weights do
  NOT fit here** — the weight-placement tension (§6, open at kickoff per the
  card).

**Live engine facts that bound the new envelope** (from the running pod's log,
GGUF path — the reference point for the FP8 re-derivation):
- `load_format=gguf, quantization=gguf, dtype=torch.bfloat16`,
  `max_seq_len=262144`, `kv_cache_dtype=fp8`, `enforce_eager=True`,
  `enable_prefix_caching=True`, `speculative_config=None`
- "All limits of multimodal modalities … set to 0, running in **text-only
  mode**" — the consequence of `--language-model-only` that this card drops
- "Available KV cache memory: **12.23 GiB**"; "GPU KV cache size: **384,176
  tokens**, Maximum concurrency for 262,144 tokens per request: **1.47×**"
  (i.e. even today only ~1.5 full-context sessions fit; the 4×100k pool-edge
  is the honest D4/HR3 envelope)
- "Free memory on device (**31.46/31.86 GiB**) on startup. Desired …
  (0.95, **30.27 GiB**). Actual usage is **17.5 GiB** for consumed memory
  (weights + non-torch), 0.54 GiB peak activation, 0.0 CUDAGraph" — the R9700
  shows 31.86 GiB; non-torch overhead measured ≈ 17.5 − 16.35 ≈ **1.15 GiB**
  with the GGUF weights
- Attention backend: "Found incompatible backend(s)
  **[TURBOQUANT, ROCM_OCTAVE, ULTRAQUANT]** with AttentionType.DECODER.
  Overriding with **ROCM_ATTN** out of potential backends:
  ['ROCM_ATTN', 'TRITON_ATTN']" — relevant to the KV-q4 question (§5.2) and to
  the guide's open-PR #60418 (TRITON_ATTN priority on gfx1201)
- The engine now also offers `--kv-cache-memory=<bytes>` as the explicit-pool
  alternative to `--gpu-memory-utilization` (log suggestion) — a new
  envelope-tuning surface in v0.33.0
- Dev-mode HTTP routes mounted (`/sleep`, `/wake_up`, `/is_sleeping`,
  `/release_kv_cache_memory`) — `VLLM_SERVER_DEV_MODE=1` is working
- `Mamba cache mode is 'align'` (GDN hybrid state, 144 MiB/seq fixed, cf-105
  R1 §3)
- MTP: `speculative_config=None` today; cf-105 R1 recorded "no MTP on AMD"
  (vLLM-on-RDNA research line) — the guide disputes this for
  `qwen3_5_mtp` (§5.1)

## 2. The current GGUF path — full wiring inventory (what the switch touches)

**`charts/vllm/`** (single app-template 5.0.1 dep, Chart.yaml L5-12):
- `values.yaml` (231 lines, all parent + `app-template:` subtree):
  - L8 `cachePvcSize: 10Gi` — top-level key read by the hand-written PVC
    template (parent-context manifest; NOT under `app-template:`)
  - L19 `modelPath` — YAML anchor `&modelPath`, the Q4 GGUF path; spliced into
    serveArgs L48-49 via `*modelPath`. Anchors resolve per-document → the
    service-level re-pin does NOT reach the render: **the retarget is the
    dual edit** (chart `modelPath`+`serveArgs` AND the service `vllm:`
    re-pin), guarded by the suite's `--model == service modelPath` assert
    (the law is documented in the chart comment L11-18 and service comment
    L597-612)
  - L47-69 `serveArgs` — rendered VERBATIM (app-template args field is not
    templated); flag order is contract-pinned by the test suite
  - L96-105 image `ghcr.io/ownyourio/vllm-rocm:main` + `pullPolicy: Always`
    + PIN-ME comment (first-build shape, C06 step 10 pins the first `:v<run>`)
  - L106-116 env (exactly four vars, pinned by test)
  - L121-145 probes (startup 60+10×90 /health)
  - L146-153 resources (4 CPU, 16Gi req / 32Gi limit)
  - L154-185 securityContext (privileged shape above; the comment carries the
    GID-486 why; no `allowPrivilegeEscalation` key — k8s rejects it with
    privileged)
  - L187-192 service `vllm` port 8000; L194-231 persistence
    (models=llama-swap ro /models; cache=vllm-cache /data; shm 8Gi Memory;
    kfd/dri hostPaths)
- `templates/pvc-vllm-cache.yaml` — hand-written RWO claim `vllm-cache`,
  `{{ .Values.cachePvcSize | default "10Gi" }}`
- `templates/NOTES.txt` — install hints (no common.yaml loader — C07 idiom,
  pinned by test)
- **Test suite (all re-pin surfaces for this plan):**
  - `tests/vllm_testlib.py` — `D4_RECIPE` L32-46 (exact flag list incl.
    `--language-model-only` L41 and `--kv-cache-dtype fp8` L38; the plan
    amends BOTH); `MODEL_PREFIX`/`MODEL_FILENAME` L55-56 (unsloth GGUF
    layout); `assert_model_path_shape` L151-158; render helpers
    (extract `vllm:` block → `-f` overlay + `--set domain/clusterName`,
    release `gpu-ai-vllm` for the peer-DNS name)
  - `tests/test_contract.py` — L89-120 `test_ac6_image_pin_is_first_build_shape`
    (pins repo `ghcr.io/ownyourio/vllm-rocm` + tag `main` + pullPolicy Always
    + PIN-ME literal — **breaks on any image switch**; the retire/repurpose
    decision's test surface); L126-139 D4 flag-order; L145-177 monitoring gate
    (`--set app-template.monitoring.annotations=false`); L214-252
    `test_ac7_workflow_exists_and_parses` (CI trigger paths incl.
    `containers/vllm-rocm/**` L223)
  - `tests/test_render.py` — L114-159 security ctx + hostPath devices;
    L161-197 GPU/RAM/shm shape (no amd.com/gpu; 4 CPU; 32Gi limit; 8Gi shm);
    L200-207 exactly-two scrape annotations; L215-236 Service
    `gpu-ai-vllm`; L239-273 persistence legs (claims `llama-swap` ro +
    `vllm-cache`, 10Gi default assert)
  - `tests/test_trio.py` — `charts.vllm` entry exactly
    `{namespace: default, ServerSideApply: "false"}`; the service `vllm:`
    block's two overrides (`modelPath` shape + `rocrVisibleDevices "0"`);
    NO `ingress.subdomains.vllm` + the skip-ruling comment must exist;
    `custom-values/gpu-ai/prod-values.yaml` and `services/gpu/prod/values.yaml`
    stay **vllm-free** (byte-pinned)
- **`.github/workflows/vllm-render-tests.yaml`** — push/PR triggers on
  `charts/vllm/**`, `containers/vllm-rocm/**`, `services/gpu-ai/prod/values.yaml`
  (L14-23 — the container path is another retire-surface); ladder:
  `helm dependency update charts/vllm` → `pytest charts/vllm/tests -v` →
  `helm lint` → chart-defaults render → service-level `-f` render (L44-59)

**`services/gpu-ai/prod/values.yaml`** (615 lines):
- L35-37 `charts.vllm` entry (the trio appset leg; rendered by
  `templates/appset.yaml` → `charts/base/templates/appset-charts.yaml`,
  appset `gpu-ai-appset`)
- L46-73 `ingress.subdomains` — the vllm skip with the D7/Q4 ruling comment
  (L48-52) and the `llama`/`ai-llama-swap` hosts; every subdomain Ingress gets
  the `llama-timeouts` ServersTransport
  (`templates/generic-ingress.yaml` + `templates/servicetransport-llama.yaml`
  `responseHeaderTimeout: 0`)
- L547-556 `llama-swap: … config: peers: vllm` — the FE hop (proxy
  `http://gpu-ai-vllm.default.svc.cluster.local:8000`, models
  `[qwen3.8-27b-vllm]`, timeouts responseHeader 1800 / connect 30,
  `filters.setParams "priority?": 5`). **Served name + body carrier are
  orthogonal to weight format (card) → this block should survive the switch
  unchanged** unless the served name or the context limit moves
- L597-615 the `vllm:` service values block — `app-template.modelPath`
  (dual-edit twin, L613) + `rocrVisibleDevices: "0"` (L615)

**`custom-values/gpu-ai/prod-values.yaml`** — 22 lines, NO vllm entry (no
secrets; pinned vllm-free by test_trio).

**`containers/vllm-rocm/`** — the GGUF overlay the card may retire:
- `Dockerfile` (98 lines): FROM `vllm/vllm-openai-rocm:v0.33.0-rocm100`
  (ledger digest `sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba`),
  pip-installs `vllm-gguf-plugin@e454affe0ca23c9dc8754ec3033270cb30622ed5`
  (git-ref ARG, the one sanctioned renovate `git-refs` directive in the dir)
  with `--no-build-isolation`, applies `carry/qwen35-import-compat.patch`
  (2-line import redirect for vLLM #60623), creates uid 65532, bakes
  `PYTORCH_ALLOC_CONF=expandable_segments:True` + cache dirs +
  `VLLM_ROCM_USE_AITER=0` (AITER prebuilds are CDNA-only), EXPOSE 8000,
  inherits `ENTRYPOINT ["vllm", "serve"]`
- `README.md` — tag→digest ledger (manual, zero renovate directives for image
  pins by contract), manual-bump procedure, interface contract (port 8000,
  /data cache, ROCR env, non-root intent)
- `carry/qwen35-import-compat.patch` — exists ONLY for the GGUF plugin's
  qwen3_5 config import; drop-condition documented
- Build pipeline: `.github/workflows/docker-build.yaml` triggers on
  `containers/**` pushes to main/dev → `:v<run_number>` (immutable) + `:main`
  (rolling); PRs build-only. **No docker daemon in agent sessions** — CI
  primary. Retiring the dir: the build workflow auto-detects changed dirs, so
  deletion simply stops its builds; the surfaces that NAME it are the chart
  image, the two test pins above, the CI trigger paths, and the README/ledger

**The llama.cpp side that shares the 500Gi PVC** (context for staging
decisions): `charts/llama-swap` (version 1.0.40, image
`ghcr.io/mostlygeek/llama-swap:unified-vulkan-266`, renovate-managed via the
`unified-vulkan-<N>` packageRule `renovate.json` L285-292); the gpu-ai
`tools` sidecar (LoRA conversion, `HF_TOKEN` from the `hf-token`
ExternalSecret, rw on `/models`) is the in-repo actor that can stage weights
on the 500Gi claim. The main llama-swap pod mounts `/models` rw
(`LLAMA_CACHE=/models`).

## 3. The official FP8 checkpoint (live-fetched 2026-11-07, HF API)

`Qwen/Qwen3.8-27B-FP8` (repo sha `c3a462cc…`, lastModified 2026-11-07T04:42:31Z,
created 2026-08-13):
- **public, `gated: false`, apache-2.0, 5.1M downloads** — no HF_TOKEN needed
  for the fetch (the `hf-token` secret stays orca's alone, cf-86 ruling)
- `usedStorage` = 30,879,676,248 B = **28.77 GiB** (card figure confirmed):
  64 per-layer shards (~383.9/372.3 MB) + `outside.safetensors` 5.59 GiB
  (vision + embeddings + GDN projections + MTP norms + lm_head, all unquantized
  BF16 per `modules_to_not_convert`) + `mtp.safetensors` 0.44 GiB +
  tokenizer (12.8 MB) / vocab / merges
- `safetensors.parameters`: F8_E4M3 24,699,207,680 + BF16 3,082,220,272 =
  27.78B params; `quantization_config {quant_method: fp8, fmt: e4m3,
  activation_scheme: dynamic, weight_block_size: [128, 128]}` — standard W8A8
  block-FP8, vLLM's stock path (cf-105 R1: "FP8 W8A8 (llm-compressor) ✅" on
  AMD; the compute path is the "young" one — vllm#28649 open,
  `--enforce-eager` neutralizes the batched-FP8 graph-capture NaN bug)
- `architectures: [Qwen3_5ForConditionalGeneration]`,
  `pipeline_tag: image-text-to-text` — **full multimodal checkpoint: vision
  tower (27-layer ViT, depth 27, hidden 1152) + MTP head + video support
  (video_preprocessor_config.json, video_token_id) all in the repo**;
  `language_model_only: false` in the config — dropping the serve flag serves
  the whole thing
- `text_config`: 64 layers GDN-hybrid (`linear_attention` ×3 :
  `full_attention` ×1, `full_attention_interval: 4`), hidden 5120,
  head_dim 256, num_attention_heads 24 / num_key_value_heads 4,
  `max_position_embeddings: 262144` (**native 256k — 1M is NOT native**, §5),
  `mtp_num_hidden_layers: 1`, `mtp_use_dedicated_embeddings: false`, mrope
  (mrope_section [11,11,10], partial_rotary_factor 0.25), vocab 248320,
  `transformers_version: 5.8.0.dev0`
- cf-105 Post Research V4 (RESEARCH.md L2469-2488) is the prior confirmation;
  its "fallback leg" was `--model Qwen/Qwen3.8-27B-FP8` +
  `--language-model-only` (values-only, no plugin) — this card is that leg
  promoted to primary, MINUS `--language-model-only`, plus the KV toggle and
  the "1m heads" question

## 4. Priority wiring live on main (the must-preserve set)

The cf-105-vllm-followup four-class amendment (plan + D1-D7, approved
2026-11-06, merged) + cf-105 D10 naming. Surfaces, exact and pinned:
- **`.opencode/opencode.jsonc` L795-812** — the three gpu-ai catalog rows:
  `qwen3.8-27b-vllm` (body.priority 5, limit.context 262144),
  `qwen3.8-27b-vllm-urgent` (1), `qwen3.8-27b-vllm-low` (9); all share the
  wire `modelID qwen3.8-27b-vllm`; provider `gpu-ai`
  (`baseURL: https://llama.spencerslab.com/v1`, 2 h header/chunk timeouts)
- **`services/gpu-ai/prod/values.yaml` L547-556** — peers.vllm block with
  floor `"priority?": 5` (the golden carries `priority?: 5`)
- **`charts/llama-swap/tests/llama_swap_testlib.py` L830-835** — `PEER_VLLM`
  single-source literal; `test_vllm_peer.py` T1-T4 (block-exact, schema
  v266, gpu-render vllm-free, golden byte-parity); golden
  `tests/golden/gpu-ai.config.yaml`
- **`.rulesync/skills/pipeline-models/SKILL.md` L39-50** — the
  single-authority four-class table (1–3→urgent 1; unset/4–7→default 5;
  8–9→low 9; 10+→background off-vLLM on llama.cpp `qwen3.8-27b-q4`; midpoint
  snap; floor follows default) + favorited rows L59-63; source of record,
  regenerated twin at `.opencode/skills/pipeline-models/SKILL.md`
- **`tests/pipeline-models/surface.sh`** — M3 (L383-418: the three catalog
  rows' modelID + body.priority 5/1/9 + no-local-shadow assert), M4 (L427-438:
  wire id in the serving authority), M7 (the class-table + floor needles)
- **`tests/notes/vllm-runbook.sh`** + **`.agents/notes/vllm-on-target-acceptance.md`**
  — the operator runbook; §5 already carries the four-class constants
  (urgent 1 / default 5 / low 9 / background 10 off-vLLM) + the victim-order
  line; the runbook's step 2.1 (weight `find`), 3.x (engine smoke), 6.x
  (benchmark pre-registration), 10 (PIN-ME) are all GGUF-path-specific and
  will need re-pinning with the format switch (the card lists this as an open
  kickoff item)
- Card #131 constraint (verbatim): "Served name + body carrier are orthogonal
  to weight format" → the switch keeps `qwen3.8-27b-vllm` unless the plan has
  a reason not to (best guess: keep — see open_questions)

## 5. "Keep 1m heads" — the two readings, grounded

**Reading A — the 1M context window** (the llama.cpp rung):
- `charts/llama-swap/values.yaml` L97-100 `ctx-1m` macro: `-c 1010000
  --rope-scaling yarn --rope-scale 4 --yarn-orig-ctx 262144 -b 512 -ub 512`
  — YaRN ×4 over the native 262144; rung `qwen3.8-27b-q8-1m` (L252-267) is
  solo-class, `--no-kv-offload` parks the ~34 GiB 1M q8_0 KV in system RAM
  (llama.cpp only). Catalog row `qwen3.8-27b-q8-1m` (opencode.jsonc L596+)
  has context 1010000.
- **Physics against this card's new envelope:** the model's native ceiling is
  262144 (§3). A 1M session at the current fp8 KV = 1,010,000 × 32 KiB ≈
  31 GiB of KV alone — impossible on a 31.86 GiB card with FP8 weights +
  vision resident (the live engine leaves ~12 GiB for ALL KV under the GGUF
  path; the FP8 path leaves ~0.4-2 GiB, §6). At KV-q4 (~16 KiB/token) one 1M
  session ≈ 16 GiB — still more than the whole FP8+vision residual. So a
  vLLM "1M" rung on the R9700 under FP8 weights is not achievable; the 1M
  capability today lives ONLY on the llama.cpp q8-1m rung (unchanged by this
  card — it is off-vLLM class 10's sibling ladder).
**Reading B — the 1 MTP head** ("1m" = 1 MTP, "heads" = the MTP module):
- `mtp_num_hidden_layers: 1` in the FP8 config; `mtp.safetensors` (0.44 GiB)
  ships in the repo; the GGUF-path live engine runs `speculative_config=None`
  (MTP unused today on vLLM).
- The owner guide (card description, attached research) uses MTP on upstream
  vLLM: `--speculative-config '{"method":"qwen3_5_mtp","num_speculative_tokens":2}'`
  (W7900 section; "MTP works on gfx1100 in upstream vLLM … acceptance
  67.6-68.2%"), and its Caveats: "**The MTP method name differs across
  sources.** pearsonkyle uses `qwen3_5_mtp`; the 7900 XTX RFC uses
  `qwen3_next_mtp`. Use whichever your pinned vLLM accepts for
  `Qwen3_5ForConditionalGeneration`."
- Counter-evidence: cf-105 R1 recorded "no MTP on AMD" [9] for the vLLM-on-RDNA
  line (the claim predates the guide's gfx1100 MTP proof). R1's GDN-state math:
  with MTP k=2 one state per verification position (~3× ≈ 0.47 GB/seq) —
  envelope-relevant.
- **Best guess adopted for planning: Reading B (keep/enable the MTP head via
  speculative decoding, method name verified against the pinned image in
  Pre Research).** Reading A is recorded as infeasible on this card under
  FP8+vision and as a reason the llama.cpp 1m rung stays the long-context
  home. If the owner actually meant 1M-context parity, the card-level answer
  is "vLLM rung keeps 262144; the llama.cpp q8-1m rung already provides 1M —
  nothing to keep on the vLLM side" — an owner ruling, flagged in
  open_questions.

## 6. The FP8 envelope question (grounded math, pre-registered)

Card: "FP8 weights ≈ 28.77 GiB on the 32 GiB R9700 leave ~1–3 GiB for KV at
0.95 util — KV-q4 plus a full envelope re-derivation … is the heart of this
card." Grounded arithmetic (live numbers + R1 §3 table L107-124 + §3):
- Device: 31.86 GiB visible; at `--gpu-memory-utilization 0.95` → 30.27 GiB
  target pool
- Weights: 28.77 GiB (all of it — vision + MTP included, no language-model-only)
- Non-torch overhead: ≈1.15 GiB measured on the Q4 run (17.5 − 16.35)
- Residual for KV + activations + GDN states: **≈0.3–0.5 GiB at 0.95**
  (R1's table said ~0.9 GiB for FP8 text-only with a 28.5 GiB estimate — the
  measured overhead and the vision-inclusive weight set land at the low end)
- fp8 KV (32 KiB/token): ~10-15k tokens ≈ one 10-15k session; the
  `--max-model-len 262144` ceiling would then admit ~0.05-0.06 "sessions"
  before preemption — **the current D4/HR3 envelope collapses under FP8+vision**
- KV-q4 (~16 KiB/token, IF supported — §5.2/open): ~20-30k tokens — a
  doubling, not a rescue; the plan must re-derive
  `max-model-len`/`max-num-seqs`/utilization (or `--kv-cache-memory`) —
  options: lower `--max-model-len` (e.g. 32-64k class), keep 4 seqs at small
  context, raise utilization toward 0.98-1.0 (the sleep/wake 2×-peak caveat,
  cf-105 Post Research V5, argues against the top), use `--kv-cache-memory`
  explicit
- The `--watermark 0.05` + `--enable-sleep-mode` + Strata coexistence
  discipline (HR6) interact: a near-full VRAM claim plus the sleep-mode 2×
  wake-peak caveat is the sharpest edge of the re-derivation
- On-target verification is operator-run (no pod-exec tier — §7)

## 7. MCP / probe surface (call shapes used; no admin tier anywhere)

- `readonly-ai-gpu-kubernetes` (the ai-gpu cluster; ns `default` unless noted):
  `pods_list_in_namespace` / `resources_list` answer **tabular rows**
  (`{columns, items[{Name, Status, …}]}`); `pods_get`, `resources_get`
  (Node/Service) answer **full objects**; `pods_log` answers a string (tail
  cap ~500-3000 lines useful). No pod-exec tier exists — on-node commands
  (rocminfo, free -h, /dev/kfd group stats) are operator-run per the card
  backlinks and cf-105 EXPLORE §7/§8
- `dev-boards` (AI-Dev board `TNQJ2BrXenZovngTS`): `preload_board`
  (lean per-card dict: id, card_number, label_ids, slug, archived, sort,
  parent_id, checklists — the five standard checklists only) and `get_card`
  (full: title, description incl. the attached research, custom_fields,
  attachments). Card #131: labels `ezGduq`+`f3sKNX` (same pair as cf-105),
  slug null, checklists: Model(s) = Qwen Dense + Qwen Flash; Services =
  gpu-ai; Type = feat; Lifecycle checked = Exploration, Pre Research,
  Planning, Test Writing, Chunk Development, Chunk Review, Final Review
  (unchecked: Agent Decides Research, Post Research, Deployment, Single
  Session); HIL checked = Planning, Chunk Review
- `webfetch` — HuggingFace API (`/api/models/…?blobs=true`, `config.json`
  raw) for the checkpoint facts; pinned-upstream reading only, no websearch

## 8. Gotchas (planning + dev)

1. **Dual-edit modelPath law**: the serveArgs YAML anchor splices the
   CHART-level `modelPath`; editing only the service block does not change
   the rendered `--model`. Chart `modelPath`/`serveArgs` + service re-pin move
   together; the suite's `--model == service modelPath` assert guards
   divergence. The FP8 switch is the next dual edit (and the testlib's
   `MODEL_PREFIX`/`MODEL_FILENAME` + `assert_model_path_shape` +
   `D4_RECIPE` are the re-pin set)
2. **serveArgs render verbatim** — no `tpl` in the args field; a values-key
   KV toggle needs the anchor-splice pattern (`kvCacheDtype: &kv` …
   `- *kv`) or a new values key the test recipe accepts; flag ORDER is
   contract-pinned (test_serveargs_values_carry_the_d4_recipe +
   test_ac2_serve_args_are_the_d4_recipe_verbatim)
3. **Image test pins the overlay**: `test_ac6_image_pin_is_first_build_shape`
   asserts repo `ghcr.io/ownyourio/vllm-rocm` + tag `main` + pullPolicy
   Always + a PIN-ME literal. Retiring the overlay (best guess, open Q4)
   flips this to the upstream `vllm/vllm-openai-rocm` pin (digest
   `sha256:4fcd39b7…83fba` is the ledger of record — same base the overlay
   sits on, so zero engine surface moves) + deletes the container dir +
   drops `containers/vllm-rocm/**` from the CI workflow paths + the
   docker-build.yaml needs no change (changed-dir detection)
4. **10Gi cache PVC vs 28.77GiB weights**: `vllm-cache` is Bound (local-path
   claims do not expand in place — recreation is the local-path way; the
   `cachePvcSize` key + hand-written template are the surface;
   test_ac4 pins the 10Gi default). Alternatives grounded: stage on the
   500Gi `llama-swap` claim (rw writer: the llama-swap `tools` sidecar or an
   operator-run fetch; the vllm pod's mount of it is readOnly) under the HF
   hub layout, or move `HUGGINGFACE_HUB_CACHE` — a plan decision (§6 open
   item "FP8 weight placement")
5. **No `--language-model-only`** changes engine behavior: the vision tower
   loads (mm limits, encoder cache, the "text-only mode" log line goes away);
   cf-105's GDN "Mamba cache mode align" + the mm-prefix attention note in
   the live log ("Disabled mm_prefix attention mode because multimodal
   inputs are configuration-disabled") flip; vision requests need
   `--limit-mm-per-prompt`-class knobs (guide uses `.image=4`)
6. **Attention backend**: the live v0.33.0 image chose ROCM_ATTN after
   overriding incompatible TURBOQUANT/ROCM_OCTAVE/ULTRAQUANT for DECODER
   attention — the guide's open-PR #60418 (TRITON_ATTN priority on
   gfx1100/gfx1201, head_size 256) and its `--attention-backend` pinning are
   research items for this card's base (Pre Research), NOT plan guesses
7. **KV-q4 support is unverified**: no prior in-repo research of 4-bit KV
   dtypes (cf-105 RESEARCH only covers `fp8`/`fp8_e4m3`); the owner phrasing
   "q4/q8" must be mapped to v0.33.0 flag values (fp8 = today's default =
   "q8"; q4 = ? — tq4_0/TurboQuant class) on ROCm gfx1201 — Pre Research
   question #1
8. **Pod shape tests pin the privileged shape** (runAsUser 0, SYS_PTRACE,
   Unconfined, hostPath kfd/dri, no amd.com/gpu, 8Gi shm) — the FP8 switch
   must NOT touch this (the GID-486 root cause; "Do not return to non-root"
   is in the card)
9. **Sleep-mode + 0.95 util wake-peak caveat** (cf-105 Post Research V5;
   runbook §8.2 gate) gets worse as the FP8 envelope fills VRAM — the
   re-derivation must account for it
10. **Repo tooling**: `export PATH=$HOME/.local/bin:$PATH` before any
    helm/pytest (helm v3.16.4 at `~/.local/bin`; without it the helm-guarded
    tests mass-skip silently); pytest runs **per-directory** (test basenames
    duplicate); no docker daemon (CI-primary builds); `rulesync generate`
    after `.rulesync/` edits (the pipeline-models surface, if touched — the
    followup D6 law: only pipeline-models carries the class mapping); `npx
    aislop ci --changes` is the PR quality gate
11. **Golden churn**: any `services/gpu-ai/prod/values.yaml` llama-swap
    block edit requires the `gpu-ai.config.yaml` golden re-capture
    (TEST_SPEC §1 pattern; T4 byte-parity); the `gpu` cluster golden stays
    untouched (charts/llama-swap is shared by BOTH clusters —
    services/gpu/prod/values.yaml is vllm-free today and pinned that way)
12. **Served-name continuity**: `qwen3.8-27b-vllm` is pinned in 5+ places
    (catalog rows ×3, PEER_VLLM, golden, runbook, surface.sh M3/M4) — a name
    change is a whole-repo re-pin; keep the name (card says orthogonal)
13. The card's attached guide is docker/LiteLLM/kustomize-shaped (W7900
    gfx1100 backend, GGZ14 MXFP4 fork, GPU Operator, PodMonitor class):
    per the card, its docker-specific parts are ignored — this repo's
    surfaces (charts/vllm + appset trio + llama-swap peers hop +
    k8s-monitoring annotations) are the translation target. The guide's
    transferable research facts: MTP method names, KV-dtype choices
    (fp8_e4m3/fp8_e5m2), `--attention-backend`, PR #60418 status,
    `vllm:kv_cache_usage_perc` (fraction) metric naming, generous startup
    probes (the guide's 30-40 min budgets vs today's 16 min — the FP8 first
    pull is 28.77 GiB, bigger than today's 18 GiB image + 16.35 GiB GGUF),
    `HF_HUB_OFFLINE=1` after first download, `--enable-auto-tool-choice`
    (the catalog rows carry `tools: true` for the q4 rung class — whether
    vLLM rows need it is a plan surface question; today's vllm rows carry no
    capabilities/tools keys)

## 9. Command set the plan can register (repo validations — no unit tests exist)

```
export PATH=$HOME/.local/bin:$PATH

# chart (the switch's primary surface)
helm lint charts/vllm
helm template vllm charts/vllm --set domain=spencerslab.com --set clusterName=gpu-ai   # chart defaults
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml')); yaml.safe_dump(d['vllm'], open('/tmp/vllm-vals.yaml','w'))"
helm template vllm charts/vllm -f /tmp/vllm-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai   # service-level
python3 -m pytest charts/vllm/tests -v

# llama-swap wire (only if peers.vllm / catalog / golden move)
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-ai-vals.yaml','w'))"
helm template llama-swap charts/llama-swap -f /tmp/gpu-ai-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai --set bitwardenIds.hf-token=test-uuid --show-only templates/configmap-llama-swap.yaml
python3 -m pytest charts/llama-swap/tests -v

# agent-context surfaces (only if the class table / runbook constants move)
rulesync generate && rulesync generate --check   # only if .rulesync/ touched
bash tests/pipeline-models/surface.sh
bash tests/notes/vllm-runbook.sh

# CI mirrors: .github/workflows/vllm-render-tests.yaml (charts/vllm + service -f render)
# quality gate: npx aislop ci --changes
```

## 10. Open questions (for coord → Pre Research / plan / owner)

- **OQ1 [Needs research: yes] — KV "q4"/"q8" → v0.33.0-rocm100 flag values on
  ROCm gfx1201.** What `--kv-cache-dtype` value (or TurboQuant/Octave
  backend surface, cf. the live log's backend override line) gives 4-bit KV,
  is it supported on this arch, and what is the bytes/token (the plan's
  envelope re-derivation hangs on it). The owner's q8 = today's `fp8`
  (fp8_e4m3) reading is grounded; the q4 side is not. Best guess: a
  kv-dtype flag value exists (tq4-class or `fp8_e4m3`/new-dtype table in
  v0.33.0's CacheConfig) and the toggle lands as a `kvCacheDtype` values key
  spliced into serveArgs by the modelPath-anchor pattern (§8.2).
- **OQ2 [Needs research: yes] — "1m heads" = MTP head (best guess adopted:
  Reading B, §5).** Verify `qwen3_5_mtp` vs `qwen3_next_mtp` speculative
  method against the pinned image's acceptance for
  `Qwen3_5ForConditionalGeneration` on ROCm (R1's "no MTP on AMD" line vs the
  guide's gfx1100 MTP proof). If the owner meant 1M context (Reading A), it is
  infeasible on this card under FP8+vision (§5) and the answer is "the
  llama.cpp q8-1m rung stays the 1M home; vLLM keeps 262144" — an owner
  ruling to confirm at the batched round. Impact: speculative-config serveArg
  (+ GDN-state envelope cost) vs none.
- **OQ3 [plan-owned] — Envelope re-derivation** at FP8+vision+KV-q4:
  `--max-model-len` (262144 vs 32/64k class), `--max-num-seqs`,
  `--gpu-memory-utilization` vs `--kv-cache-memory`, the sleep/wake 2×-peak
  interaction, and the pre-registered benchmark expectations that replace
  runbook §6's D4/HR3 numbers. Grounded arithmetic in §6; on-target
  verification stays operator-run (§7).
- **OQ4 [plan-owned, best guess adopted: RETIRE `containers/vllm-rocm`] —**
  the overlay exists solely for the GGUF plugin + carry patch (both dropped
  with the format). Best guess: point `charts/vllm` at the upstream
  `vllm/vllm-openai-rocm:v0.33.0-rocm100` base (the overlay's own FROM —
  digest already in the ledger; engine behavior identical modulo the absent
  plugin/env bakes), delete the container dir + its CI trigger path + the
  three image test pins; keep the `PYTORCH_ALLOC_CONF` / cache-dir / AITER-0
  env decisions in the chart (they move from the overlay's ENV to the pod
  env, or are re-verified as still-needed). Impact: test_ac6 image test,
  CI workflow paths, the C06-style PIN-ME/ledger procedure.
- **OQ5 [plan-owned] — FP8 weight placement on storage** (§6/§8.4): 10Gi
  `vllm-cache` cannot hold 28.77 GiB. Options grounded: (a) stage under the
  500Gi `llama-swap` claim in HF hub layout via the tools sidecar /
  operator fetch, `--model` = that directory (the vllm pod's /models mount is
  readOnly — staging happens elsewhere, once); (b) grow `cachePvcSize` to
  ~40Gi + recreate the local-path claim (the Triton/HF scratch stays the
  vllm pod's own). Best guess: (a) — matches the card backlink's storage map
  and the existing 500Gi claim; (b) is the values-key path. Affects
  test_ac4 (10Gi pin), the runbook step 2.1 `find` target, and first-start
  duration
- **OQ6 [plan-owned] — Served name + catalog rows: KEEP `qwen3.8-27b-vllm`**
  (card: orthogonal to weight format; 5+ pinned surfaces). Only a context
  change (OQ2 Reading A or the envelope shrink) would touch the rows'
  `limit.context` — a whole-repo re-pin (catalog, surface.sh M3, runbook,
  PEER_VLLM stays name-only). Best guess: name stable, context re-pinned only
  if the plan moves `--max-model-len`
- **OQ7 [Needs research: yes — light] — Attention-backend choice for
  v0.33.0 on gfx1201 with head_dim 256** (live: ROCM_ATTN after the
  TURBOQUANT override; guide: PR #60418 open, TRITON_ATTN preferred on
  RDNA). Whether a `--attention-backend` pin enters the new serveArgs;
  interacts with OQ1 (KV dtype may gate backend choice — the guide notes
  `fp8_e5m2` KV "keeps ROCM_ATTN")
- **OQ8 [owner, batched-round] — the attached guide's R9700 section is the
  MXFP4-fork path (GGZ14/stilldeadcode:0.9.3, "early dev, experimental, not
  production hardened")** while requirement #1 mandates the official FP8
  stock-loadable path. Confirm the fork stays out of scope (best guess: yes —
  the requirement's "no OOT plugin, no carry patches" reading covers it; the
  guide's fork numbers (137.7 t/s c=1, 416 t/s c=8) are recorded as the
  out-of-scope ceiling, not a plan target)
- **OQ9 [plan-owned] — multimodal limits + tool-calling surface**: with
  vision on, the plan sets `--limit-mm-per-prompt`-class flags (guide
  precedent `.image=4`); whether the three vllm catalog rows gain
  `capabilities.input: [text, image]` (the llama.cpp visual rungs carry it;
  the vllm rows today carry none) — an owner-visible picker surface

## 11. What does NOT change (verified present on main)

- The peers.vllm hop + floor 5 + golden (unless OQ6 moves the name/context)
- The four-class table, favorited rows, surface.sh M3/M4/M7, the runbook's
  §5 priority section (constants stable; the runbook's weight/engine steps
  change per OQ3/OQ5)
- `services/gpu/prod/values.yaml` (vllm-free, 8 GiB box) + `custom-values/gpu-ai`
  (no vllm entry)
- The pod security/device shape (§8.8), the monitoring annotations (§8.10
  D8 law: exactly two), the reloader annotation, the 16-min-class startup
  probe envelope (OQ3 may re-size it — the guide argues 30-40 min for a
  bigger first pull)
- Strata + the llama.cpp roster + the qwen3.8-27b-q4 background class (class
  10 stays off-vLLM)
