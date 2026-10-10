# 2026-10-09 feat — gpu-ai Qwen3.8 roster, tools sidecar, 500Gi PVC, llama reroute

**Status: implemented** on branch
`please-implement-home-coder-opencode-plan-2026-10-/fusion-mv1qu0pq`
(not committed/pushed — pending user go-ahead).

Executed from the external plan
`/home/coder/.opencode/plan/2026-10-09-feat-gpu-ai-qwen38-models-llama-reroute.md`.
Skills loaded: `llama-swap`, `helm-chart-creation` (the plan's
`helm-bjw-s-chart`/`kubernetes-skill`/`gitops-workflows` are not synced into
this worktree's `.agents/skills/`; the bjw-s API was taken from the pinned
app-template 5.0.1 schema and existing charts instead).

> Fusion note (2026-10-10): three parallel implementations of this plan were
> merged. This record describes the fused result: attempt 1's full-scope base
> (vendored b10015 converter, five-model roster, `llama-cpp` ingress keying,
> HF_TOKEN on main+tools) plus attempt 3's operator docs (`README.tools.md`),
> chart packaging hygiene (`.helmignore`), vendored-code attribution
> (`LLAMA_CPP_LICENSE`) and provenance pinning (`converter-source.json` +
> integrity test), plus attempt 3's CI hardening (read-only permissions,
> timeout, service-umbrella lint/template steps). Rejected: attempt 2's
> dropped `qwen38-orca-f16` model (the sharded F16 works via `-hf` suffix
> matching, same mechanism as the chart's existing `:BF16` models), attempt 2's
> homegrown converter (the vendored upstream passes a real synthetic
> PEFT→GGUF conversion test) and its `llama` ingress key (renders two
> Ingresses named `llama-ingress`), and attempt 3's reduced scope (no
> routing) — the plan's reroute steps are implemented here.
>
> Post-fusion user review (2026-10-10) reverted two plan items:
> (a) the gpu 2Gi memory-request fix (the VM is deliberately memory-limited
> for now; the user will raise it soon — gpu keeps the 4Gi default), and
> (b) the `localOnly` template gating entirely (both `proxy-ingress.yaml`
> and `proxy-ingress-sso.yaml` are back to baseline; `llama-small` is a
> plain hub entry — its public Ingress, external-dns record and SSO-path
> ingress all render and are accepted as dangling/unused per user).

## What changed

### charts/llama-swap
- `scripts/llama_tools.py` — NEW operator CLI for the tools sidecar:
  `status`, `prepare`, `convert-cyber`, `download <artifact>` (consent gate),
  `verify`, `smoke-test <model>`. Stdlib-only (runs before the venv exists),
  temp-file + atomic rename everywhere, Range-resume for downloads, HF_TOKEN
  attached only to huggingface.co URLs and never logged.
- `scripts/convert_lora_to_gguf.py` — vendored from llama.cpp **b10015**
  (the image's exact build). NOTE: the plan's URL
  (`convert/convert_lora_to_gguf.py`) 404s — at b10015 the script lives at
  the repo root.
- `scripts/conversion/{__init__,base,qwen}.py` — NEW vendored subset of the
  `conversion` package b10015's converter imports (lazy module loading;
  Qwen3.8 arch → `qwen` only).
- `scripts/gguf-py/gguf/*.py` (11 files) — NEW vendored repo-local gguf-py
  0.19.0: PyPI `gguf` stopped at 0.9.1 and lacks `MODEL_ARCH.DFLASH` that
  b10015's qwen.py requires (caught by the synthetic-tensor test).
- `templates/configmap-tools.yaml` — NEW, embeds all 16 scripts as flat keys
  (data size 750 KiB < 1 MiB etcd limit; commented so future additions watch
  the ceiling).
- `templates/secret-hf-token.yaml` — NEW ExternalSecret (audiomuse-ai
  pattern), guarded on `bitwardenIds.hf-token` so gpu renders clean.
- `templates/pvc-llama-swap-default.yaml` — size now
  `{{ .Values.modelsPvcSize | default "300Gi" }}`.
- `values.yaml` — added `bitwardenIds: {}`, `modelsPvcSize: 300Gi`,
  `persistence.tools` (ConfigMap → /app/tools readOnly, globalMounts),
  `containers.tools` sidecar (python:3.12.15-slim-bookworm, sleep infinity,
  disabled by default, no GPU, drops ALL caps).
- `tests/` — NEW: `test_llama_tools.py` (atomic publish, Range resume,
  redaction, consent gate, status/verify, staging), `test_convert_lora.py`
  (synthetic Qwen3 PEFT adapter → real conversion → GGUF assertions incl.
  b10015's `.weight.lora_a/b` naming, and loud-failure on unexpected
  tensors), `test_vendored_provenance.py` (every vendored file matches the
  sha256 pinned in `scripts/converter-source.json`; every vendored file is
  embedded in the ConfigMap manifest), `test_render.py` (helm template
  contracts: tools container off/on, ExternalSecret guard, PVC 300Gi/500Gi,
  ConfigMap contents, no sentinels). **30 passed.**
- `README.tools.md` — NEW operator runbook (commands, credential scoping,
  converter provenance, cyber phase-2 activation).
- `scripts/converter-source.json` — NEW provenance pin: upstream repo, tag
  `b10015`, commit `12127defda4f41b7679cb2477a4b0d65ee6a0c8f`, per-file
  sha256 (all 16 files re-fetched and verified byte-identical 2026-10-10).
- `scripts/LLAMA_CPP_LICENSE` — NEW: llama.cpp MIT license for the vendored
  subset (attribution; not mounted at runtime).
- `.helmignore` — NEW: keeps `tests/` and Python caches out of the packaged
  chart (does NOT touch `scripts/`, which `configmap-tools.yaml` embeds via
  `.Files.Get`).
- `.github/workflows/llama-swap-tools-tests.yaml` — NEW: pytest + helm
  lint + helm template on push/PR touching `charts/llama-swap/**`, the
  gpu/gpu-ai service values, proxy-local, or the custom-values entry
  (python 3.12; torch from the CPU wheel index; gguf NOT pip-installed —
  the vendored gguf-py is authoritative; `permissions: contents: read`,
  20-minute timeout; also lints/templates the gpu-ai, gpu and proxy-local
  umbrellas).

### services/gpu-ai
- `prod/values.yaml` — ingress entry `llama-cpp` with `serviceName: llama`
  (gpu-ai now serves `llama.<domain>`; mirrors gpu's convention — keying the
  entry `llama` as the plan sketched would render two Ingresses both named
  `llama-ingress`). Filled the `llama-swap:` block: `modelsPvcSize: 500Gi`,
  `bitwardenIds.hf-token: OVERRIDE_VIA_CUSTOM_VALUES`, five Qwen3.8 models
  (`qwen38-orca`, `qwen38-ara`, `qwen38-rana`, `qwen38-humanlike`,
  `qwen38-orca-f16`; `qwen38-cyber` staged as a comment for phase 2),
  q38 macros, union matrix `sets.main`, tools sidecar enabled.
- **HF_TOKEN on BOTH main and tools containers** (user-approved deviation —
  see below).

### custom-values/gpu-ai
- `prod-values.yaml` — `llama-swap.bitwardenIds.hf-token:
  2ebdd082-4996-440b-a8c1-b4de01130738`.

### services/gpu
- `prod/values.yaml` — `llama-cpp.serviceName: llama` → `llama-small` (gpu
  stops claiming `llama.<domain>`). `modelsPvcSize` untouched → 300Gi
  default, cache preserved.
- **NOT done (user-directed, 2026-10-10 review):** the planned 2Gi memory
  request fix for the gpu llama-swap FailedScheduling was reverted. The VM
  is deliberately memory-limited right now; the user will raise it soon and
  the chart's default 4Gi request rides as-is until then.

### services/proxy-local
- `templates/proxy/proxy-ingress.yaml` + `proxy-ingress-sso.yaml` —
  **unchanged** (user-directed, 2026-10-10 review): no `localOnly` template
  gating at all; both files are back to baseline.
- `prod/values.yaml` — `llama.target: llama-cpp` → `gpu-ai`; `ai-llama-swap`
  hub route commented out (disabled, gpu-ai serves it directly; one-entry
  uncomment to restore); NEW `llama-small` entry: `target: llama-cpp`, SSO
  shape mirrored from `llama`, no `localOnly` flag — the public Ingress
  (+ external-dns record) and SSO-path ingress render like any other hub
  entry and are accepted as dangling/unused; LAN clients resolve
  llama-small.<domain> → proxy-local via internal DNS.

### services/proxy-remote
- No change (llama-small is LAN-only by design).

## Deviations from the plan (all surfaced to and approved by the user
during implementation, 2026-10-09)

1. **HF_TOKEN also on the main container.** Re-verification found
   `orcarouter/Qwen3.8-27B-Uncensored-GGUF` is **gated** (terms + token) and
   `aboliterant`'s RANA files 401 unauthenticated; `-hf` downloads run in
   `main`. The plan scoped the token to the tools sidecar only, which would
   have broken first-load of `qwen38-orca`/`-f16`/`-rana`. Fix: gpu-ai
   injects `HF_TOKEN` (secretKeyRef `hf-token/token`) into main too; the rana
   bootstrap curls pass `Authorization: Bearer` when the token is set (shell
   `dl()` helper — bare `$HF_TOKEN` is invisible to llama-swap's `${macro}`
   engine, verified against v240 source). The app-template 5.0.1 schema
   forbids `optional:` on secretKeyRef, so the injection lives in gpu-ai
   service values (where the secret is guaranteed), not the chart default.
   **Prereq: the HF account behind the Bitwarden token must have accepted
   the orcarouter license gate.**
2. **Converter vendored with its real b10015 dependency closure.**
   b10015's `convert_lora_to_gguf.py` imports `torch`, `transformers` and the
   repo's `conversion/` + `gguf-py/` packages (the plan assumed the older
   numpy/safetensors-only script). Minimal lazy-import subset vendored
   (~750 KiB total in the ConfigMap); venv requirements extended to
   torch (CPU wheel) + transformers + safetensors + huggingface_hub + numpy +
   pyyaml + tqdm. `prepare` stages the packages on the PVC; the script's own
   `gguf-py` probe finds the staged copy.
3. **orca F16 is sharded** (`-00001-of-00002`/`-00002-of-00002`): no single
   F16 file exists; `-hf repo:F16` suffix-matching downloads both shards
   (same mechanism the chart's `:BF16` models use). Config unchanged, comment
   added.
4. **gpu-ai ingress keyed `llama-cpp` (serviceName `llama`)** instead of the
   plan's key `llama` — the plan's shape renders two Ingresses both named
   `llama-ingress` under gpu-ai's generic-ingress template.
5. Vendored converter path: `convert_lora_to_gguf.py` at the llama.cpp repo
   root, not `convert/` (plan URL 404s).

## Verification performed (pre-merge)

Re-run during the 2026-10-10 fusion pass (helm v3.16.4, python 3.14,
torch 2.14.1+cpu, transformers 5.19.0):

- `helm lint charts/llama-swap` ✓; `helm template` default ✓ (no
  ExternalSecret, single `main` container, PVC 300Gi, /app/tools readOnly
  mount, 0 sentinels).
- gpu-ai slice render ✓ **with the custom-values overlay applied**
  (production semantics): ExternalSecret remoteRef carries the real UUID,
  PVC **500Gi**, main+tools containers each with `HF_TOKEN` secretKeyRef,
  main env keeps `TZ`+`LLAMA_CACHE` after merge, union roster = 41 models
  (36 chart defaults + 5 new, cyber absent), tools ConfigMap 16 keys at
  750 KiB (< 1 MiB etcd limit), zero sentinels.
- gpu slice render ✓: no ExternalSecret, PVC 300Gi, main keeps the chart's
  default 4Gi request (2Gi fix reverted per user), single container.
- gpu-ai umbrella render ✓: `llama-ingress` (host llama.<domain>, backend
  gpu-ai-llama-swap, external-dns) + `llama-cpp-ingress` internal hop;
  all Ingress names unique; existing `ai-llama-swap-ingress` intact;
  `llama-timeouts` ServersTransport present.
- gpu umbrella render ✓: `llama-small-ingress` (host llama-small.<domain>,
  backend gpu-llama-swap, external-dns), zero `llama-ingress` left.
  Pre-existing duplicate ingress names (langflow/n8n/searxng/supabase,
  key == serviceName) are untouched baseline behavior.
- proxy-local umbrella render ✓: `llama-service` → `gpu-ai.spencerslab.com`;
  `llama-small-service` → `llama-cpp.spencerslab.com`;
  `llama-small-local-ingress` + `llama-small-local-sso-ingress` (both LAN
  ClientIP-gated IngressRoutes) + `redirect-llama-small` middleware present;
  public `llama-small-ingress` (external-dns enabled) and
  `llama-small-sso-ingress` DO render — dangling/unused by design (no
  localOnly gating per user); `ai-llama-swap` renders nothing; `llama`
  public + SSO + LAN routes intact; both proxy templates byte-identical to
  baseline.
- proxy-remote ✓ untouched (step 15).
- Vendored converter integrity ✓: all 15 python files + LICENSE re-fetched
  from `raw.githubusercontent.com/ggml-org/llama.cpp/b10015` and diffed —
  byte-for-byte identical; tag → commit `12127def` confirmed via GitHub API;
  hashes pinned in `scripts/converter-source.json` and guarded by
  `test_vendored_provenance.py`.
- `pytest charts/llama-swap/tests` — **30 passed** (incl. the real
  synthetic-adapter → GGUF conversion through the vendored b10015 converter).

## Still user-owned (per plan)

- gpu VM memory increase (then the llama-swap pod's Pending/FailedScheduling
  clears on its own — the 2Gi request fix was declined, 2026-10-10).
- DNS: `gpu-ai.spencerslab.com` → 10.0.99.151; LAN split-horizon
  `llama-small.spencerslab.com` → 10.0.77.54 (note: since the localOnly
  gating was dropped, external-dns will also publish a public
  llama-small.<domain> record → proxy-remote; the LAN split-horizon entry
  overrides it for LAN clients — accepted per user).
- PVC recreation to 500Gi on gpu-ai when convenient (local-path can't
  expand; ArgoCD will show that one PVC OutOfSync until then — expected).
- Merge to main / push — agent work stops at local files.
- Post-merge steps 6–11 of the original plan (sync checks, smoke loads,
  cyber phase-2 walkthrough commands, Grafana watch).
