# Friction — 2026-10-feat-llama-swap-config-generation

Append-only. Known workarounds — do not rediscover them. Status: open | fixed | ignored.

- [open] Third-party skills/agents here may spawn no nested subagents (depth
  limit). Resolution used: research STORM fan-out fell back to sequential
  in-session interviews. Later agents: don't plan on sub-subagents.
- [open] `webfetch` to raw/API URLs can route through an expiring file-proxy
  returning 404s. Resolution used: direct `curl` for GitHub/HF API + raw file
  fetches works. Keep using curl for those.
- [fixed] DECISIONS.md said tests target "gpu-moe" but no `services/gpu-moe`
  exists. Resolution: confirmed with user — gpu-moe = the `gpu` cluster
  (`services/gpu`, Radeon 780M 8 GiB VRAM / 64 GiB RAM). Recorded in DECISIONS.
- [open] llama.cpp sources moved (`hf.cpp` → `common/hf-cache.cpp` +
  `download.cpp`); locate via GitHub tree API rather than old paths.
- [fixed] agent-test session crashed mid-run on a provider error. Resolution:
  resumed via sessionID; re-validated on-disk artifacts (byte-checked goldens,
  re-collected suite) before continuing. If a pipeline session crashes, RESUME
  it — don't re-derive.
- [open] No docker daemon in this worktree env. `test_autogen_integration`
  image/merged-`-validate` cases skip; they are opt-in gated evidence
  (`LLAMA_SWAP_IMAGE_EVIDENCE=1` with a daemon) — an acceptance requirement,
  not a CI gate. Don't mistake the skips for green.
- [open] `edit` tool flakes matching em-dashes in some YAML/doc files.
  Resolution used: patch via shell python for those spots (also hit by the test
  session; C02 dev confirmed).
- [open] `aislop ci --changes`-style `scan --changes` scopes 0 files on an
  unpushed worktree branch (no base ref). Resolution: run directory-scoped
  `aislop scan <dir>` on touched trees + grep evidence for changed files.
- [open] `/tmp/opencode` tooling can vanish between sessions (test session's
  helm+venv were gone by C01 dev). Resolution: probe first, rebuild helm
  v3.16.4 + `/tmp/opencode/ag-venv` from the pinned tarball when missing.
- [open] Pinned autogen tool's `validate` subcommand REJECTS base.yaml form and
  even the declared config — only `generate` parses base.yaml. Assert against
  TEST_SPEC.md §5.1's re-expressed criterion, not the plan-file's original
  C03-2 wording.
- [open] Declared-CM "byte" figures 22547/31334 are Python len(str) CHARS, not
  UTF-8 bytes (gpu is 22561 bytes — 7 em-dashes ×3). Compare by sha, not by
  re-counting lengths, or you'll flag a false parity regression.
- [open] HF gated repos (orcarouter): anonymous API listing of siblings works,
  but /resolve returns 401 — header-level tensor checks need HF_TOKEN
  (unavailable locally). Use file-structure evidence instead.
- [open] unsloth sharded GGUFs: shard 1 is metadata-only (`n_tensors=0`) —
  tensor-name fit probes must read shard 2+. GGUF tensor-info field order is
  name→n_dims→dims→dtype→offset; a dtype-first misread yields silently empty
  tables.
- [open] `RUN_HF_CHECK=1` cases sit behind the module-level
  `LLAMA_SWAP_EVIDENCE` gate — set BOTH env vars for the HF-live run.
- [open] `/tmp/opencode/ag-venv` has the autogen console script but NO pytest;
  gated runs use system `python3 -m pytest` (9.1.1 user-site) with
  `PATH=/tmp/opencode/bin:$PATH` for helm. `aislop scan` takes exactly ONE
  directory arg per invocation — dir-scan + per-file attribution.
- [open] helm 3.16's sprig `dig` cannot descend through slices — use a small
  define helper (see `llama-swap.firstMountPath` in _helpers-llama-swap.tpl)
  instead of dig for paths crossing list structures.
