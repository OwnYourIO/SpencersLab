# 2026-10-13 feat — llama endpoints: real context limits in OpenCode + 1M variants on gpu-ai

## Request

1. "Go through the GPU-AI and GPU-MoE connections and correct them — OpenCode
   detects them as 200k, they're all bigger than that."
2. "Add support for 1m context in gpu-ai for the q8 versions of: qwen3.8 27b,
   qwen3.6 35b, kat-coder (all). Each model should have a 256k and a 1m
   version."

## Skills loaded

llama-swap, opencode (V2 docs: models/providers), helm-chart-creation context
from earlier in the session.

## Research findings

**200k detection.** OpenCode V2 docs (opencode.ai/v2/docs/models): models not
in the models.dev catalog fall back to *assumed* 200,000-token context /
32,000-token output — "not detected capabilities. Set accurate `capabilities`
and `limit` values when known." llama-swap's `/v1/models` exposes no
context-length field (verified live: id/name/description/meta/status only),
so explicit `limit.context` in `agent-config.jsonc` is the fix. The user had
already started (limits on `kat-coder-q8`, `qwen38-rana` in gpu-ai; the
`qwen3-vl-4b*` set in gpu-moe); this change completes the pattern
(context-only, matching their entries; output stays at the 32k fallback).

**Config layout (current main).** `agent-config.jsonc` is now V2-style
`providers`: `gpu-ai` (llama.<domain>, 78 models), `gpu-moe`
(llama-moe.<domain>, 67 models), plus disabled legacy `llama`
(llama-cpp.<domain>) and `spencerslab` entries.

**Context values per model family** (from chart cmds):
- home-3b-v3(-gpu): `-c 8192`
- all qwen3-vl-* (incl. :caption/:tags profiles): `-c 16384`
- qwen38-humanlike: `-c 131072`
- everything else text/MoE: `${ctx-256k}` (262144)
- 1M variants: `${ctx-1m}` (`-c 1010000`, YaRN ×4 from native 262144)
- whisper-large-v3: audio model, no context limit — intentionally no `limit`.

**1M feasibility.** HF configs (fetched live):
- Qwen3.8-27B (`qwen3_5_text`): 64 layers, **hybrid** — 16 full-attention +
  48 linear-attention (interval 4), 4 KV heads × 256 dim, native
  `max_position_embeddings: 262144`. 1M q8 KV ≈ 34GB.
- KAT-Coder-V2.5-Dev (`qwen3_5_moe_text`): same family/param count as
  Qwen3.6-35B-A3B (34.66B, 40 layers, 10 full-attn, 2 KV heads × 256 dim,
  native 262144). GGUF sizes identical to q35 (Q8 36.91GB / Q6 30.05GB /
  Q4_K_M 21.39GB). 1M q8 KV ≈ 10.7GB.
- Qwen3.6-35B-A3B: hybrid (verified 2026-10-11). 1M variant already exists in
  the chart (`qwen3.6-35b-a3b-1m`, same Q8_0 + `${ctx-1m}`) and is already in
  gpu-ai's matrix set → nothing to add for q35.
- gpu-ai node: 125GB RAM, 32 CPUs, 1 AMD GPU (VRAM not exposed via API; the
  256k q38q8 already loads weights ~27GB + 8.7GB KV on it).

**Design decision — `--no-kv-offload` on all 1M variants:** parks the KV in
the 125GB RAM (34GB q38 / ~11GB kat+q35) instead of VRAM, so the VRAM budget
is unchanged from the 256k versions; attention runs slower ("slow is fine"
per the operator's established expectation for CPU-heavy configs). No MTP on
`qwen3.8-27b-q8-1m` (draft-mtp over CPU-resident KV untested; 1M variants
trade speed for context anyway).

## Changes

### `services/gpu-ai/prod/values.yaml`
- 4 new models under `llama-swap.config.models` (additive merge with chart):
  `qwen3.8-27b-q8-1m` (plain Q8 + `${ctx-1m}` + `--no-kv-offload`, q38 flags
  inlined because `${q38-common}`'s -b/-ub would clobber `${ctx-1m}`'s 512
  batches), `kat-coder-q4-1m` / `kat-coder-q6-1m` / `kat-coder-q8-1m`
  (`${ctx-1m}` + `${moe}` + `${flash-and-q8}` + `--no-kv-offload` — same
  combo as the chart's proven `qwen3.6-35b-a3b-1m`).
- Matrix: new vars `q38q81m`, `katq41m`, `katq61m`, `katq81m`; `sets.main`
  alternation extended with all four (scalar must restate the full union).

### `agent-config.jsonc`
- `limit.context` added to every model in the `gpu-ai` and `gpu-moe`
  providers (8k home / 16k VL / 128k humanlike / 256k text / 1,010,000 the
  1m entries); disabled legacy providers left as-is; whisper skipped (audio).
- New model entries in the `gpu-ai` provider: `qwen3.8-27b-q8-1m`,
  `kat-coder-q4-1m`, `kat-coder-q6-1m`, `kat-coder-q8-1m` (limit 1,010,000).
  Not added to `gpu-moe` — the 1M variants are gpu-ai service overrides, not
  in the gpu box's roster.
- 256k+1M pairing check: qwen3.8-27b-q8 ✓/✓, qwen3.6-35b-a3b-q8 + existing
  qwen3.6-35b-a3b-1m ✓/✓, kat-coder q4/q6/q8 ✓/✓.

## Validation

- `helm lint charts/llama-swap` clean; `helm template` with the extracted
  gpu-ai `llama-swap:` subtree renders: 49 merged models, all four 1m cmds
  correct, `${ctx-1m}` = `-c 1010000 --rope-scaling yarn --rope-scale 4
  --yarn-orig-ctx 262144 -b 512 -ub 512`, matrix vars/sets include the new
  IDs, no sentinels.
- agent-config.jsonc: JSONC strips + parses as valid JSON; per-provider limit
  census: gpu-ai 78 models (only whisper without limit), gpu-moe 67 (only
  whisper), context buckets 8192/16384/131072/262144/1010000.

## Notes / follow-ups

- OpenCode picks limits up on config reload (no restart needed for a fresh
  session; in-flight requests keep old settings).
- gpu-moe provider still lists the full chart roster; models without the
  8GB-fit override OOM on that box (documented in the 2026-10-11 debug plan).
  Not touched here — limits were the ask.
- First 1M load on gpu-ai is worth watching via
  `https://llama.spencerslab.com/logs/stream/upstream` (FA + CPU-KV combo on
  b11515: expected to work, FA falls back to CPU with CPU-resident KV; if a
  load errors on flash-attn, drop `--flash-attn on`/`${flash-and-q8}` from
  the failing entry — KV doubles to f16 size in RAM, still fits).
- RAM headroom on gpu-ai with the worst combo (q38q8-1m + kat-q8-1m are
  matrix alternatives, never concurrent): ~34GB KV + 27GB GPU weights +
  system — comfortable in 125GB.

## Addendum (same session): kill agent-config.jsonc, split global vs project config

Operator direction: OpenCode reads `opencode.json`, not `agent-config.jsonc`;
the repo file was only live via symlinks. New wiring (executed 2026-10-13):

1. `~/.config/opencode/opencode.json` and `~/.config/kilo/kilo.jsonc`:
   symlinks replaced with real copies of the old agent-config.jsonc content
   (machine-local, no longer version-controlled). Both verified materialized
   before any repo change.
2. `agent-config.jsonc` removed from the repo (`git rm`); the only other
   references (AGENTS.md ×2, helm-chart-creation SKILL.md, a gpu values
   comment) updated to the new wiring.
3. `.opencode/opencode.json` is now the version-controlled, self-sufficient
   project config for this repo (merges over global): all 39 lab MCP servers
   (37 fleet + the 2 ai-gpu ones already here), `permissions` (71 rules),
   `disabled_providers`, `default_agent` and `skills` paths. Agents need no
   JSON duplication — OpenCode already loads them from the
   `.opencode/agents → .agents/agents` symlink (24 .md agents, superset of
   the 18 inline in the old global).
4. **Providers moved to the globals** (operator decision after step 3): the
   corrected `gpu-ai` (78 models) + `gpu-moe` (67 models) blocks — every
   model with `limit.context`, four new 1M entries — were surgically spliced
   into both `~/.config/opencode/opencode.json` and `~/.config/kilo/
   kilo.jsonc` (replacing the legacy blocks incl. the disabled
   `llama`/`spencerslab` providers that pointed at the retired
   llama-cpp host). Machine-wide endpoints, used from other projects too →
   global, not repo. Pre-change backups: `*.pre-provider-move.bak`.
5. Validated: all three config files parse as JSONC; 39 servers in project;
   both globals carry identical provider blocks (no-limit: whisper only).

Deliberately NOT changed: the materialized globals keep their full legacy
content (inline agents block, UI prefs, providers without limits) — other
projects and Kilo still consume them; drift is now manual (documented in
AGENTS.md).
## Addendum 2 (2026-10-15): Q8 cache/no-cache split + post-lockup crash check

**Model split (operator request; naming swapped 2026-10-15):** llama.cpp
hard-disables `cache_reuse` when a multimodal projector is loaded, so each Q8
daily driver comes in two variants — the **base ID is the text-only CACHING
version** (`--no-mmproj` + `--cache-reuse 256`; 256 tokens of drift tolerance
for mutating agentic prompts), and the **`-visual` sibling** keeps the mmproj
(cache_reuse disabled there):
- gpu-ai: `qwen3.8-27b-q8` (caching, MTP kept) / `qwen3.8-27b-q8-visual`;
  `qwen3.6-35b-a3b-q8` (caching) / `qwen3.6-35b-a3b-q8-visual` (chart cmd).
  Matrix: base IDs reuse the chart vars; new `q38q8v` / `q35q8v`.
- gpu box: its single `qwen3.6-35b-a3b-q8` (already `--no-mmproj` from the
  8GiB fit) gains `--cache-reuse 256` — base-ID-is-caching holds there too.
- Global OpenCode config: IDs/names swapped, text-only capabilities on the
  caching variants, image input on the `-visual` ones (machine-local file).
Render-verified both umbrellas; helm lint clean.

**Crash check (same night):** device-lost crashes CONTINUE on
gpu-ai qwen3.8-27b-q8 — 11 reload cycles in the log window, every crash at
n_tokens 59–64k (progress 0.93–1.00, t≈275–319s): the SAME band as before
the `amdgpu.lockup_timeout=30000` cmdline change. With a 30s ring budget the
~2–3s deep-KV FA dispatches could not trip the watchdog at this depth, so the
parameter almost certainly is NOT active on the booted kernel (likely the
edited systemd-boot entry isn't the one being booted — 12 entries present).
Verify on ai-gpu: `cat /proc/cmdline | grep amdgpu` and
`cat /sys/module/amdgpu/parameters/lockup_timeout`; match the booted entry by
its initrd hash in /proc/cmdline against /boot/efi/loader/entries/*.conf.
If crashes persist WITH the param active, next lever = drop MTP from the
caching variants (upstream A/B: MTP-off survives 125k+).
