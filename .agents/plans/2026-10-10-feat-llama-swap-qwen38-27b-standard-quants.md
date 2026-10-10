# Plan: add Qwen3.8-27B standard quants to llama-swap chart (feat)

- **Date:** 2026-10-10
- **Agent:** code (direct small change, plan written after the fact)
- **Skills loaded:** llama-swap, helm-chart-creation

## Goal

User request: add **Qwen3.8-27B (normal/official)** to the llama-swap chart as
standard, with the typical 4/6/8/16-bit quants. gpu-ai's service override
already carries the fine-tune family (orca, heretic-ara, RANA, humanlike); the
plain model was missing from the chart default roster.

## Research performed

- HF repo survey for the plain model's GGUFs:
  - `unsloth/Qwen3.8-27B-GGUF` (6.4M downloads): UD-Q4_K_{S,M,XL}, UD-Q5_K_*,
    UD-Q6_K{,_M,_L,_XL}, UD-Q8_K_{L,XL}, plain Q4_0/Q4_1/Q8_0 — **no 16-bit**.
  - `Qwen/Qwen3.8-27B` (official): safetensors only, no GGUF.
  - `ggml-org/Qwen3.8-27B-GGUF`: **BF16**, Q4_K_M, Q8_0 + mtp/mmproj files.
  - `bartowski/Qwen3.8-27B-GGUF`: full K-quant ladder, no 16-bit.
- Chart conventions read from `charts/llama-swap/values.yaml`: dense Qwen
  models use `unsloth/<repo>:<QUANT>` + `${server-cmd} ${threads} ${ctx-256k}
  ${flash-and-q8}`, `ttl: 0`, key pattern `<model>-q<bits>`; the one 16-bit
  precedent (`qwen3.6-35b-a3b-bf16`) uses key suffix `-bf16`, name "(BF16)",
  description "BF16 (no quant)".

## Changes

`charts/llama-swap/values.yaml` — four new entries under `config.models`,
inserted at the top of the roster (before `qwen3.6-27b-q6`):

| Key | Source | Quant |
|---|---|---|
| `qwen3.8-27b-q4` | `unsloth/Qwen3.8-27B-GGUF` | `UD-Q4_K_XL` |
| `qwen3.8-27b-q6` | `unsloth/Qwen3.8-27B-GGUF` | `UD-Q6_K_XL` |
| `qwen3.8-27b-q8` | `unsloth/Qwen3.8-27B-GGUF` | `Q8_0` |
| `qwen3.8-27b-bf16` | `ggml-org/Qwen3.8-27B-GGUF` | `BF16` |

All follow the dense-model template (`${server-cmd}`, `${threads}`,
`${ctx-256k}`, `${flash-and-q8}`, `proxy: http://localhost:${PORT}`,
`ttl: 0`). Comment block notes why 16-bit comes from ggml-org.

Decisions:
- unsloth's XL dynamic-imatrix builds chosen for Q4/Q6 (no plain Q4_K_M/Q6_K
  published for this model; XL is unsloth's top-quality file per bit level).
- BF16 = the "16 quant" (only 16-bit GGUF available from a standard provider).
- No `-hf` gating/MTP wiring: plain dense serving, same as the qwen3.6-27b
  entries. gpu-ai keeps its MTP-specced fine-tunes separately.

## Effect on consumers

- **gpu** cluster: chart defaults apply verbatim (empty `llama-swap:` block);
  roster-only change — models load on demand.
- **gpu-ai** cluster: Helm deep-merges the service `config.models` over chart
  defaults, so the four standard entries coexist with the existing qwen38-*
  fine-tunes; no service values edit needed.

## Follow-up change (same session): MTP for the unsloth entries on gpu-ai

User requested MTP speculative decoding for the three unsloth-sourced models
on gpu-ai only.

Research:
- Range-fetched the GGUF header of `Qwen3.8-27B-UD-Q4_K_XL.gguf` (12MB,
  tensor table complete through blk.64): **no `blk.*.mtp.*` tensors** —
  unsloth GGUFs do not embed MTP layers, so `--spec-type draft-mtp` alone
  would fail. Separate draft file required (precedent: `qwen38-rana`).
- ggml-org/Qwen3.8-27B-GGUF publishes `mtp-Qwen3.8-27B-{Q4_0,Q8_0,BF16}.gguf`.
- llama.cpp master `common/arg.cpp` confirms `-hfd` / `--spec-draft-hf`
  ("Same as --hf-repo, but for the draft model"); image b10015 is newer, so
  the flag is available. `-hfd` caches via the same LLAMA_CACHE=/models path.

Changes:
- `services/gpu-ai/prod/values.yaml` → `llama-swap.config.models`: override
  entries for `qwen3.8-27b-q4/q6/q8` (full cmd restated, sibling q38 style):
  `-hf unsloth/...` + `-hfd ggml-org/Qwen3.8-27B-GGUF:mtp-Qwen3.8-27B-Q8_0.gguf`
  + `-c 262144 --spec-type draft-mtp --spec-draft-n-max 2 ${q38-common}`,
  `ttl: 300`. No `capabilities:` — unsloth files have no embedded mmproj.
  `qwen3.8-27b-bf16` also overridden with MTP (user follow-up): same Q8_0
  ggml-org draft + `--spec-type draft-mtp --spec-draft-n-max 2 ${q38-common}`,
  `ttl: 180` per the qwen38-orca-f16 reference-build precedent. Verified its
  ggml-org BF16 header has no embedded MTP tensors either (848 blk.* tensor
  refs, zero mtp hits) — hence the separate draft for all four.
- Matrix wiring (both files): chart `config.matrix.vars` gains
  `q38q4/q38q6/q38q8/q38bf16`, chart `main` set alternation gains the four
  vars; gpu-ai's `main` set (scalar-replace) restates them per its
  "must restate the chart's full alternation" convention. Vars map itself
  deep-merges from the chart, so gpu-ai needed no new var lines.

Validation:
- `helm lint charts/llama-swap` — clean.
- Chart-only render: four plain entries + matrix vars/set, no MTP (gpu keeps
  standard behavior).
- gpu-ai render via extracted service block: all four qwen3.8-27b-* entries
  show the MTP cmd (`-hfd` count = 4, override won), all five qwen38-*
  fine-tunes survive the merge, matrix main set contains chart + fine-tune
  vars, zero `OVERRIDE_*` sentinels in both renders.

## Follow-up change (same session): deprecated chat-template-kwargs cleanup

Live logs showed llama.cpp warning: `Setting 'enable_thinking' via
--chat-template-kwargs is deprecated. Use --reasoning on / --reasoning off
instead.` Verified replacements in llama.cpp master `common/arg.cpp`:
`enable_thinking` → `-rea/--reasoning on|off|auto`, `reasoning_effort` →
`--reasoning-effort LEVEL`, `preserve_reasoning` → `--reasoning-preserve`
(default enabled). The old config's `preserve_thinking` key was not a
llama.cpp-managed kwarg at all.

Changes in `services/gpu-ai/prod/values.yaml` (zero `chat-template-kwargs`
left, incl. comments):
- `q38-think` macro (orca, ara, future cyber) → `--reasoning on` +
  `--reasoning-effort medium` + `--reasoning-preserve`.
- `qwen38-humanlike` inline → `--reasoning on --reasoning-effort low`.
- `qwen38-rana` inline (inside the sh -c script) → same three flags on the
  continuation line; `sh -n` re-checked OK.

Validation: gpu-ai helm render OK, flags present in macro def + humanlike +
rana, zero sentinels.

## Validation (initial roster change)

- `helm lint charts/llama-swap` — 0 failures (icon INFO only).
- `helm template gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com`
  — renders 6 resources; all four `qwen3.8-27b-*` keys present in the
  `llama-swap-config` ConfigMap with correct `-hf` refs and macros intact;
  `grep -c OVERRIDE_` on the render = 0.

## Follow-up change: rana repo went private → mirror rewrite (option B)

Live check after the user agreed to the orcarouter gate: orca loaded, rana
still failed. `aboliterant/Qwen3.8-27B-RANA-abliterated-GGUF` now returns
HTTP 401 on the metadata API (private — no request-access flow exists for
private repos; HF search still indexes it stale). Rewrote `qwen38-rana`:

- Main weights: `-hf mradermacher/Qwen3.8-27B-RANA-abliterated-GGUF:Q6_K`
  (public mirror, `gated=false`; note its dot-separated file naming).
- mmproj: bootstrap curl kept (explicit `--mmproj` is version-proof vs -hf
  sidecar auto-fetch), re-pointed at the mirror's
  `Qwen3.8-27B-RANA-abliterated.mmproj-f16.gguf` — URL verified 200→CDN.
  HF_TOKEN branch dropped from `dl()` (public files, no auth needed).
- MTP draft (user chose option B, experimental):
  `-hfd ggml-org/Qwen3.8-27B-GGUF:mtp-Qwen3.8-27B-Q8_0.gguf` — the official
  base-model MTP module; trained on stock Qwen3.8-27B, not the abliteration,
  so acceptance may be poor. Comment in values says to drop the spec flags if
  it hurts more than it helps.
- exec remains one physical line (SanitizeCommand constraint, above).

Validation: SanitizeCommand-replica argv check (`sh -c` + single 998-char
script), `sh -n` OK, mmproj URL 200, zero `aboliterant` refs remain, helm
lint clean, gpu-ai render OK, 0 sentinels, 0 trailing backslashes.

## Not in this change

- No version bump (CI does it on merge).
- `ServerSideApply: "false"` for llama-swap in `services/gpu-ai/prod/values.yaml`
  still risks the >256KB last-applied annotation on the tools ConfigMap
  (observed failing in ai-gpu events today) — flagged to user separately.
- ai-gpu cluster's `hf-token` ExternalSecret still failing: Bitwarden item
  `2ebdd082-4996-440b-a8c1-b4de01130738` doesn't resolve — user action.

## Correction (2026-10-10, later session): --reasoning-effort does not exist on b10015

The reasoning cleanup above was validated against llama.cpp **master**, but the
image's llama-server is **b10015**. Master has `--reasoning-effort LEVEL`
(arg.cpp:3728); b10015 does not (its reasoning flags stop at `--reasoning`,
`--reasoning-format`, `--reasoning-budget`, `--reasoning-budget-message`,
`--reasoning-preserve`). Live evidence: after the cleanup rolled out, every
model carrying `--reasoning-effort` (qwen38-orca, -ara, -rana, -humanlike,
-orca-f16 via the q38-think macro) exited prematurely at arg-parse — before
any download — while the flagless `qwen3.8-27b-*` quants loaded fine. This
masqueraded as "can't pull the abliterated model" for rana (a public,
ungated repo — verified: metadata 200, files resolve anonymously).

Fix applied in `services/gpu-ai/prod/values.yaml`:
- `--reasoning-effort <level>` replaced by a template-kwarg passthrough
  `--chat-template-kwargs '{"reasoning_effort":"<level>"}'` — exactly the
  pre-cleanup behavior for effort (only `enable_thinking` was the deprecated
  kwarg; b10015 warns on that key alone). `--reasoning on` and
  `--reasoning-preserve` are valid on b10015 and stay. Three sites: q38-think
  macro (medium), humanlike inline (low), rana inline (medium, escaped quotes
  inside the sh -c string; extracted script re-passes `sh -n`).
- Guard comment added above q38-think so the flag is not re-introduced until
  the image's llama.cpp gains it.
- rana's bootstrap `curl` gained `--retry-all-errors` (HF's resolver was
  observed returning transient 401s on this public repo; plain `--retry`
  does not retry 4xx).

Status of the two "Not in this change" items above, as of this correction:
- tools ConfigMap >256KB annotation risk: FIXED in 232d6aec2 (ConfigMap now
  embeds only llama_tools.py + converter-source.json, 26 KiB; prepare fetches
  the pinned converter files).
- hf-token ExternalSecret: now `Ready: True` / "secret synced" (checked live);
  the earlier Bitwarden resolution failure cleared.

Still user-owned: orcarouter/Qwen3.8-27B-Uncensored-GGUF is gated — orca and
orca-f16 will 403 until access is requested with the hf-token account, even
with the flag fix in place.

Validated: helm lint (chart + gpu-ai + gpu umbrellas), gpu-ai chart render
(no `--reasoning-effort` anywhere rendered, kwargs + preserve present, 0
sentinels), `sh -n` on the extracted rana script, pytest 33 passed.

## Correction #2 (2026-10-10, later session): rana backslash fix vs. llama-swap SanitizeCommand

The rana fix in the correction above (backslash continuations inside the
quoted `/bin/sh -c "..."` script) was validated with `sh -n` on the raw
script — but llama-swap never passes the raw script to the shell. Its
`SanitizeCommand` (internal/config/commands.go, byte-identical v240/v262)
strips trailing `\` (keeping the newline) before POSIX-shlex splitting, so
inside the quotes the newlines reached the inner sh as command separators:
`exec llama-server` ran with zero args and the flag lines died as "not
found" commands. Live evidence persisted after rollout (rana still exited
prematurely). The same latent bug has broken the whisper bootstrap since it
was written. Fixed properly during the v262-vulkan-b11515 image bump: both
bootstrap scripts restructured so every inner command is complete on one
line with continuation only via trailing `&&`/`||` (legal POSIX newline
after an operator), validated through a replica of SanitizeCommand + shlex +
`sh -n`. See the 2026-10-09 reroute plan record, section "Real rana fix
found along the way".
