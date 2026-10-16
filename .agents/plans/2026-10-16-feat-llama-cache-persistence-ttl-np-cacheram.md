# Feat: llama cache persistence + gpu-ai trio coexistence (dense + MoE + embedding) (feat)

- **Date:** 2026-10-16
- **Branch/worktree:** pending commit (main checkout)
- **Skills loaded:** llama-swap (session), opencode (session)
- **Research:** SearXNG → llama.cpp PR #16391 (host-memory prompt caching),
  jessequinn.info `--cache-ram` write-up, llama.cpp discussions
  13606/4130/20572; flag semantics verified against **b11515 source** (the
  running image `v262-vulkan-b11515`): `common/common.h:634-640`
  (`n_cache_reuse=0`, `cache_idle_slots=true`, `cache_ram_mib=8192`
  defaults), `common/arg.cpp` (`-cram/--cache-ram` MiB — `-1` unlimited,
  `0` disabled, **per llama-server process**; `--cache-idle-slots` default
  on, requires cache-ram; `--cache-reuse N` min chunk for KV-shift reuse;
  `-np` default resolves to 4 slots).
- **Live measurements (readonly-ai-gpu-kubernetes):** node ai-gpu capacity
  131,151,632 Ki ≈ **125 GiB**, 90.9 GiB available with q38q8 np=1 running;
  system + other pods anon ≈ 6 GiB; q38 pod working set 28.9 GiB (weights +
  MTP; the np=1 KV pool ~8.7 GiB shows at node level).

## Problem (operator request, builds on 2026-10-15 debug)

1. Walk-away gaps: agent asks a question, operator returns ~1 h later — KV
   cache busted. Cause was `ttl: 300` → llama-swap unloaded the model after
   5 min idle → process death kills all slot KV + RAM prompt cache.
2. Concurrent subagents: with `-np 1` all sessions shared one slot
   (0.34–0.52 LCP churn); queued requests hit client timeouts.
3. NEW: allow **3 models loaded at once on gpu-ai** — one dense running,
   plus the MoE and an embedding model always ready. No embedding model
   existed in the roster.

## Mechanics (verified)

- **Slots (`-np`) = live cache tier.** Under `kv_unified` the pool is
  `np × ctx` tokens, preallocated at load. Per-slot contexts stay capped at
  `ctx`; a lone session can grow into unused pool space.
- **`--cache-ram` = warm tier, PER PROCESS** (each llama-swap model is its
  own llama-server) — NOT a shared pool. Idle sessions beyond `-np` are
  saved to host RAM on slot reassignment and restored on prefix match;
  within a process the store LRU-evicts the oldest entry when full
  ("making room for prompt cache entry, removing oldest entry" — observed
  live at the 8 GiB default cap).
- Across processes nothing coordinates: weights + ΣKV pools are hard
  preallocations, cache-ram fills softly up to its cap; the sum must fit
  physical RAM (swap disabled on ai-gpu), so it is budgeted below.

## Changes

### `services/gpu-ai/prod/values.yaml`

**Caching variants (`qwen3.8-27b-q8`, `qwen3.6-35b-a3b-q8`):**

| Knob | Before | After |
|---|---|---|
| `ttl` | 300 (q38) / 0 (q35) | key removed → chart default `ttl: 0` = never auto-unload; eviction only via matrix swap |
| `-np` | 1 (q38) / implicit 4 (q35) | **2** each (512k pool each: ~17.8 GiB KV dense, ~5.9 GiB KV MoE) |
| `--cache-ram` | default 8192 | **16384** (q38) / **10240** (q35) |
| `--cache-reuse` | 256 | 256 (unchanged) |

**New model `qwen3-embedding-0.6b`** (gpu-ai only): official
`Qwen/Qwen3-Embedding-0.6B-GGUF:Q8_0`, `--embeddings` (serves
/v1/embeddings; chat disabled on that process), `-c 8192 -np 2
--cache-ram 0 -ngl 99`, `ttl: 0`. ~0.7 GiB weights + ~0.1 GiB KV.

**Matrix restructure** — old: one giant alternation `(...everything...) &
homecpu` (only one GPU model resident). New:

```
main: "(q38q4|q38q6|q38q8|q38q8v|q38bf16|q27bq6|q27bq8|coderq6|coderq8|q38orca|q38ara|q38rana|q38hum|q8bq4|q8bq8|homegpu)
       & (q35q8|q35q8v|q35q6|q30q4|q30q8|katq4|katq6|katq8) & emb06 & homecpu"
solo: "(q35bf16|q35b1m|q38f16|q38q81m|katq41m|katq61m|katq81m|all VL|wsp) & homecpu"
```

= ONE dense + ONE MoE + embedding + homecpu resident at once; switching
within a group evicts only that group's member (MoE/embed caches survive
dense switches). F16 / 1M / VL / whisper models stay in `solo`: they evict
the trio when requested and trio members reload on demand (PVC-cached
weights).

**Startup preload hook:** `hooks.on_startup.preload: [qwen3.8-27b-q8,
qwen3.6-35b-a3b-q8, qwen3-embedding-0.6b]` — the trio is ready after pod
(re)starts; the main set permits all three concurrently.

### Memory budget (worst case, trio resident, caches full)

| Item | GiB |
|---|---|
| q38q8 weights + MTP | ~29 |
| q38 KV pool (np=2, 512k) | ~17.8 |
| q35q8 experts (RAM) + non-expert + KV pool (np=2) | ~31.9 + 2.5 + 5.9 |
| embedding | ~1 |
| cache-ram caps (16 + 10 + 0) | 26 |
| system + other pods | ~6 |
| **Total vs 125 GiB** | **≈ 121 → ~3 GiB buffer** (operator-specified target) |

Options weighed with operator (np=3-MoE or 32 GiB cache variants overflowed
the box); chosen: **np=2/np=2, cache 16+10 GiB**.

### `services/gpu/prod/values.yaml`

`-np 1` pinned on the q35 override — closes a latent hole in the 2026-10-11
8GiB fit: the unpinned llama-server default is 4 slots, and pool = `np ×
ctx` would preallocate 4 × 262144 × ~10.9 KB ≈ 10.6 GiB KV on the 8 GiB
card (np 2 → ~5.7 GiB + 2.48 GiB weights also busts it). `-np 1` keeps the
pool at ~2.66 GiB as originally budgeted. No embedding model on this box
(gpu-ai-only definition; keeps the tight budget intact); concurrent agents
queue on the single slot by design.

## Validation

- `helm lint` + `helm template` both umbrellas: pass. Chart untouched
  (`git diff charts/` empty); chart pytest 33/33.
- gpu-ai merged ConfigMap: hooks.preload trio; `main`/`solo` sets parsed;
  every matrix var used, every model has a var, no dangling targets;
  q38q8 `-np 2 --cache-ram 16384`, q35q8 `-np 2 --cache-ram 10240`,
  embedding `--embeddings -np 2 --cache-ram 0`, both ttls absent at service
  level (chart `ttl: 0` merges).
- gpu merged ConfigMap: embedding absent, no hooks, q35 `-np 1`, sets
  unchanged.

## Rollout (user-driven)

1. Merge → ArgoCD syncs gpu-ai + gpu; reloader restarts llama-swap pods.
   gpu-ai preloads the trio after start (~1–3 min from PVC cache).
2. Verify: `GET /running` on llama.gpu-ai shows all three; interleave two
   agent sessions → `/api/metrics/activity` shows `cache_tokens` ≈ full
   prompt per stream; walk away and return → fast restore, no cold prefill;
   request a VL model → trio evicts, then reloads on the next chat request.
3. Watch node RAM the first day (target ≈121 GiB peak, ~3 GiB buffer);
   cache-ram caps are soft — raise with a one-line values change if
   monitoring shows headroom.

## Notes / follow-ups

- Matrix `solo` evictions are the designed pressure valve; if VL/whisper
  churn becomes annoying, give them their own off-peak windows or a
  dedicated endpoint later.
- `--slot-save-path` (disk-persistent KV surviving process restarts) remains
  the next-level lever — not adopted.
- Companion client-side change (2026-10-15): opencode ≥2.0.29 +
  headerTimeout/chunkTimeout 2 h in `~/.config/opencode/opencode.json`
  (machine-local, done).
- Loki/Grafana 502 (noticed 2026-10-15 while debugging) still unresolved —
  separate ticket.
