# PLAN: Strata engine (R9700/ROCm) exposed through gpu-ai llama-swap
feature: 2026/2026-10-cf-77-feat-strata-llama-swap

## Goal
Add the Strata inference engine (Qwen3.8-Flash-Next IQ3_S, R9700-alone + expert-arena-in-RAM mode, PR #3636 recipe) to the gpu-ai cluster, **exposed through the existing llama-swap surface** (llama.<domain> / ai-llama-swap): a new, cluster-internal `strata` pod (chart `charts/strata/`) whose in-pod llama-swap supervisor launches and owns `strata serve`, with the existing gpu-ai llama-swap gaining a `peers:` entry that routes `qwen3.8-flash-next-strata` requests to it. Ship repo deliverables — Strata container image, internal chart, peers/service wiring, secrets — plus human-owned host-prep and enablement runbooks; every card `[VERIFY]` rides as a research target or an on-target runbook step.

Out of scope: host kernel/BIOS/GRUB/firmware/OCuLink changes (runbook only); Strata split mode (8060S+R9700) — deferred in STATE.json; a second public host (Q4: exposure through the existing surface only); running live benchmarks (consented operator step post-merge; landing on main is user-owned).

## Architecture decision (Q4 answer: "through the existing llama-swap" — mechanism chosen: (b))
**Separate internal engine pod, routed by peers — the existing llama-swap deployment stays byte-shape-identical except additive config.** Rejected (a-merge): llama-swap spawns processes inside its OWN container, so merging strata into the working instance means a union image (Vulkan llama.cpp + ROCm strata + supervisor) replacing the golden `unified-vulkan-266` pin that 58 roster IDs and the renovate packageRule ride — maximum blast radius on the working service. Rejected (a-sidecar): a second container in the existing pod keeps main unprivileged but forces the POD to gain hostPath volumes + 420s termination grace + `strategy: Recreate` pod-wide (a 100 GiB arena must never ride a RollingUpdate overlap — #2257) and couples every strata config edit to a llama.cpp restart via the reloader. Rejected (b-with-engine-as-PID1): bare `strata serve` pins the arena at pod boot, violating the lazy posture and offering no unload control. Chosen (b) confines every Strata risk (privilege, pinning, cold boot, crashes) to one new pod; the llama.cpp surface is untouched; guide Step 4's pod-shape facts (Recreate, 420s grace, no memory cap) apply where they belong. **Trio rule deviation, deliberate:** `charts.strata` gets NO `ingress.subdomains` entry — the proxy leg exists for externally-facing services; strata is ClusterIP-internal by the operator's Q4 ruling (recorded in DECISIONS).
RAM reality (Q2 answer): lazy load, **`ttl: 0`, NO preload** — first request pays the cold arena pin (minutes; 150×10s startup probe + `healthCheckTimeout` absorb it); once loaded the ~100 GiB arena stays resident PERMANENTLY — the llama.cpp trio swaps normally only until the first Strata request lands; `POST /api/models/unload/:id` against the inner instance is the documented escape (runbook). Preload flip stays a values toggle.

## Commands
- `helm dependency update charts/strata && helm lint charts/strata && helm template charts/strata --debug`
- `helm template strata charts/strata --set domain=test.example.com --set bitwardenIds.strata-api-key=test-uuid` — valid manifests, zero `OVERRIDE_` sentinels; WITHOUT the bitwardenIds set: renders clean with no ExternalSecret
- `python3 -m pytest charts/strata/tests/ -q` — new render-contract suite (harness pattern: `charts/llama-swap/tests/llama_swap_testlib.py`)
- peers gate: the existing `charts/llama-swap` still lints/renders unchanged (`helm lint charts/llama-swap && helm template charts/llama-swap --debug`), and the gpu-ai service block's rendered llama-swap `config.yaml` carries a `peers:` entry pointing at the strata ClusterIP service URL (extract-and-render recipe from helm-chart-creation Validation)
- both rendered llama-swap configs (outer with peers, inner strata config) validate against llama-swap's `config-schema.json` (skill URL; vendored under tests/ with provenance note)
- wiring greps: `grep -n "strata" services/gpu-ai/prod/values.yaml` (must show the `charts:` entry, the `llama-swap.config.peers` entry, and the `strata:` values block; must NOT show an `ingress.subdomains.strata*` host); `grep -n "strata-api-key" custom-values/gpu-ai/prod-values.yaml`
- containers: `docker build containers/strata/` — best-effort locally; authoritative build is `docker-build.yaml` on the pushed PR branch (`local: false`)

## Skills (later agents MUST load)
`/llama-swap` (peers, macros, SanitizeCommand, probe notes), `/container-creation` (Dockerfile + ARG-pin + CI), `/helm-chart-creation` (+ `references/storage-and-secrets.md` for the Bitwarden stores, `references/values-and-appset.md` for value loading) and `/helm-bjw-s-chart` (app-template values API).

## MCP grounding
Read-only only: `readonly-ai-gpu-kubernetes` (llama-swap pod/deployment facts, node allocatable), `global-searxng` + web fetch for research targets. No `admin-*`. No pod-exec anywhere — host/pod commands live in the runbook for the operator.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | containers/strata image (gfx1201 + gfx1151 engines + llama-swap supervisor) | M | 1 | [] | publishes the image interface (binary paths, entrypoint contract) pre-agreed in DECISIONS |
| C02 | charts/strata internal engine pod (supervised llama-swap + strata serve) | M | 1 | [] | independent of C01 given the frozen image interface |
| C03 | gpu-ai wiring: appset entry + peers route on existing llama-swap + secrets | M | 2 | [C02] | peers URL targets the rendered strata Service name; appset entry needs the chart dir |
| C04 | host-prep + enablement + validation runbooks (human-owned steps) | M | 3 | [C02, C03] | documents final names/gates; written last so it matches what shipped |
| C05 | Strix-alone fallback (gfx1151 model entry + matrix alternation) | M | 2 | [C01, C02] | consumes the bundled second engine binary (C01) and the inner config schema (C02) |

## Wave order
1. C01, C02 (independent; run in id order)
2. C03, C05 (both need C02; independent of each other — run in id order)
3. C04

## Human-owned steps (must ride the final report)
1. **Create Bitwarden item `strata`** (fields store, custom field `api_key`) and supply its UUID → replaces the `PENDING`-placeholder in `custom-values/gpu-ai/prod-values.yaml` (`strata-api-key`). Until then the strata pod strands on CreateContainerConfigError — quarantined by design (inner `apiKeys: []`, outer peers entry points at a URL, not a secret).
2. Host prep per the C04 runbook: kernel/firmware (≠ linux-firmware 20251125), GRUB/sdbootutil cmdline `ttm.pages_limit=29360128 ttm.page_pool_size=29360128 amd_iommu=off`, BIOS UMA/ReBAR/ASPM, OCuLink x4 check, k3s `LimitNOFILE`/`LimitMEMLOCK` drop-ins, on-target `rocminfo` to fix `ROCR_VISIBLE_DEVICES` (values default `"0"`).
3. **Pre-sync gates**: host prep confirmed + UUID landed BEFORE first Strata request; never request Strata while a trio session is live-after-warm (RAM law, Q2).
4. PR creation/merge + ArgoCD sync + the one-attempt consented load/bench protocol (repo law: landing on main is user-owned).

## Risks / assumptions
- Node is assumed to have the R9700 present with an OCuLink x4 link (card premise); step-0 runbook gates live enablement; a missing/degraded link pivots to the C05 Strix-alone fallback (in scope per Q8).
- Perf numbers are single-machine, single-quant (IQ3_S), Docker-on-Ubuntu, engine 0.2.2 (line now 0.2.5/0.2.6) — pin a version, re-bench after upgrades; repo acceptance is render/greps only, the ~10%-of-PR-#3636 gate is on-target.
- Exact engine flag set is NOT public (PR #3636 fork branch) — strata args live in ONE values-driven profile ConfigMap (single edit point), hypothesis-gated by research + on-target `strata serve --plan`.
- `ttl: 0` + lazy means the first post-deploy Strata request can take minutes and, if the arena pin fails mid-load, leaves a half-pinned engine — startup probe width (150×10s) and the 420s grace are the designed absorbs; the inner unload escape is runbook-documented.
- Shared models claim: weights land on the existing 500Gi `llama-swap` PVC under `/models/strata/` (Q3) — RWO multi-pod same-node mount assumed on the single-node local-path hostPath backing; runbook verifies, chart pins `nodeSelector` to the same node implicitly (single-node cluster).
- Image build can't be proven until the branch is pushed (CI); `:main` + `pullPolicy: Always` is the documented new-container tag policy until the first `:v<run>` Renovate pin.

## Open questions (post-rework)
- **O1 (new, best-guess taken):** outer peers entry: route the alias `qwen3.8-flash-next-strata` through the inner instance which then does its own model resolution (outer peers = blanket URL proxy, model names must match inner IDs) vs. also adding an outer-level model entry — best guess: peers-only, model IDs are inner's; the outer `peers:` schema exact key names (per-peer `url`/`apiKey`/`timeouts`) ride as a research/verification target. Impact: cosmetic config shape, not architecture.
- **O2 (new, best-guess taken):** cold-load minutes vs inner `healthCheckTimeout` default — best guess 1800s (guide's 1200–1500 class) as a values key on the strata chart; the outer per-peer request timeout for the first call must tolerate minutes (per-peer `timeouts` in the peers schema, [VERIFY]) else the outer returns 504 while the inner still loads. Runbook + research cover both.
- (Q1 slug kept; Q2 lazy+`ttl: 0`; Q3 shared PVC; Q4 through-existing-llama-swap exposure; Q5 sentinel+placeholder with human pre-sync gate; Q6 layered image, 2B escalation; Q7 values-configurable `ROCR_VISIBLE_DEVICES` default `"0"`; Q8 Strix fallback in scope as C05, split deferred — all resolved by the answer round.)

## Research targets (post-plan, coordinator launches agent-research)
- Upstream image: exact repo/tag `ghcr.io/niko1221/strata:<ver>-rocm-gfx120x` AND the `rocm-gfx1151` sibling tag (existence, version alignment, binary layout inside each — C05's bundling hinges on it), current Strata release + digests; TheRock 7.14.1 gfx120X tarball name/sha + hipBLASLt gfx1201 tuning-table existence (2B escalation facts).
- `strata serve` CLI: flag names/validity for the 3.2 set (`--prefill`, `--kv-grow`, `--kv int8`, `--max-context`, numeric `--expert-cache` (#1715), `--vram-reserve-mib`, `--resident-budget-gib`, `--spec*`/`--mtp*`, `--prompt-cache-every` (#4206/#3090), `--conversation-cache-*`, `--host/--port/--api-key`), profile `--config` JSON schema, `STRATA_KV_GROW_HOLD` + `STRATA_PREFILL_CPU_SHARE=auto` semantics, current-version ulimit self-raise (PR #2398/#2399), `strata bench run` suite names, gfx1151 §5 fast-config env set for C05.
- llama-swap: `peers:` entry schema (URL shape, per-peer apiKey/timeouts, SSE passthrough), whether a peers route can pass `${env.*}` substitutions, `checkEndpoint` against Strata's `/health` (fallback `/v1/models`), `unloadTimeout`/stop-signal semantics for a ~100 GiB engine, current repo image version (`unified-vulkan-266` = llama-swap v266) peers-feature availability, `hooks.on_startup.preload` as the flip.
- IQ3_S (ISTA-DASLab) on-disk size for Qwen3.8-Flash-Next + repo path/quant tag; feeds PVC-capacity math and `--resident-budget-gib` sizing.
- PR #3636 fork branch (`jiayeZhu/Strata@bench-strix-halo-r9700-022`) exact args, if readable.

## On-target [VERIFY] items → C04 runbook (human-owned, NOT research, NOT repo)
Kernel/firmware versions + Tumbleweed package names, GRUB/sdbootutil cmdline (`ttm.pages_limit=29360128 ttm.page_pool_size=29360128 amd_iommu=off`), BIOS UMA/ReBAR/ASPM, OCuLink `lspci -vv` 16GT/s x4, `ROCR_VISIBLE_DEVICES` index via `rocminfo` (or `GPU-<uuid>` form), render/video numeric GIDs, SELinux-vs-AppArmor, k3s systemd drop-ins, THP (#771), in-container ulimits, bench reproduction within ~10% of the PR #3636 R9700-alone column — one-attempt consented protocol inherited from the flash-next OOM ticket.
