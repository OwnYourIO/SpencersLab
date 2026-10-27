# PLAN: Strata engine (R9700/ROCm) exposed through gpu-ai llama-swap
feature: 2026/2026-10-cf-77-feat-strata-llama-swap

## Goal
Add the Strata inference engine (Qwen3.8-Flash-Next IQ3_S, R9700-alone + expert-arena-in-RAM mode, PR #3636 recipe) to the gpu-ai cluster, **exposed through the existing llama-swap surface** (llama.<domain> / ai-llama-swap): a new, cluster-internal `strata` pod (chart `charts/strata/`) whose in-pod llama-swap supervisor launches and owns `strata serve`, with the existing gpu-ai llama-swap gaining a `peers:` entry that routes the Strata model IDs to it. Ship repo deliverables — Strata container image, internal chart, peers/service wiring, secrets — plus human-owned host-prep and enablement runbooks.

Out of scope: host kernel/BIOS/GRUB/firmware/OCuLink changes (runbook only); Strata split mode (8060S+R9700) — deferred in STATE.json; a second public host (Q4: exposure through the existing surface only); running live benchmarks (consented operator step post-merge; landing on main is user-owned).

## Architecture decision (unchanged by research; mechanism = (b))
**Separate internal engine pod, routed by peers — the existing llama-swap deployment stays byte-shape-identical except additive config.** Rejected (a-merge): llama-swap only spawns processes inside its own container → union image replacing the golden `unified-vulkan-266` pin (58 roster IDs + renovate ride it). Rejected (a-sidecar): forces pod-wide `strategy: Recreate` + 420s grace + hostPath volumes on the working deployment and couples every strata edit to a llama.cpp restart. Rejected (b-engine-PID1): pins the arena at boot, violating the lazy posture. Chosen (b) confines every Strata risk to one new pod; guide Step 4's pod shape (Recreate, 420s grace, no memory cap) applies where it belongs. **Trio rule deviation, deliberate:** `charts.strata` gets NO `ingress.subdomains` entry — internal-only by the operator's Q4 ruling (DECISIONS).
RAM law (Q2 + R3, research-corrected): node confirmed **128 GB**. The verified IQ3_S R9700-alone footprint is ~47 GiB pinned arena + 24 GiB conversation cache + KV/pack/page-cache headroom (RESEARCH §4/§5) — still cannot coexist with the llama.cpp trio's ~90–119 GiB preallocation. Posture: **lazy load, `ttl: 0`, NO preload** — first request pays the cold arena pin (minutes; 150×10s startup probe + `healthCheckTimeout: 1800` absorb it); once loaded the arena stays resident PERMANENTLY — trio swapping coexists only until the first Strata request lands (`POST /api/models/unload/:id` on the inner instance is the documented escape; the ~47 GiB page-locked unload needs the per-model `unloadTimeout` raised — RESEARCH §3, C02). Preload flip stays a values toggle.

## Commands
- `helm dependency update charts/strata && helm lint charts/strata && helm template charts/strata --debug`
- `helm template strata charts/strata --set domain=test.example.com --set bitwardenIds.strata-api-key=test-uuid` — valid manifests, zero `OVERRIDE_` sentinels; WITHOUT the bitwardenIds set: renders clean with no ExternalSecret
- `python3 -m pytest charts/strata/tests/ -q` — render-contract suite (harness pattern: `charts/llama-swap/tests/llama_swap_testlib.py`)
- peers gate: `helm lint charts/llama-swap && helm template charts/llama-swap --debug` still green; the gpu-ai service block's rendered outer `config.yaml` carries `peers.strata` with `proxy: http://<rendered-svc>:8080` (**no `/v1` suffix** — paths append verbatim, RESEARCH §3), an explicit `models: [qwen3.8-flash-next-strata]` list (C05 appends the strix ID), and `timeouts.responseHeader: 1800`
- config-schema validation target: `https://raw.githubusercontent.com/mostlygeek/llama-swap/v266/config-schema.json` — **the v266 tag, not main** (matches the deployed pin; main-only keys would false-fail — RESEARCH "Implications/Validation")
- wiring greps: `grep -n "strata" services/gpu-ai/prod/values.yaml` (must show the `charts:` entry, the `llama-swap.config.peers` entry WITH its `models:` list, and the `strata:` values block; must NOT show an `ingress.subdomains.strata*` host); `grep -n "strata-api-key" custom-values/gpu-ai/prod-values.yaml`
- containers: `docker build containers/strata/` — best-effort locally; authoritative build is `docker-build.yaml` on the pushed PR branch (`local: false`)

## Skills (later agents MUST load)
`/llama-swap` (peers, macros, SanitizeCommand, probe notes), `/container-creation` (Dockerfile + ARG-pin + CI), `/helm-chart-creation` (+ `references/storage-and-secrets.md` for the Bitwarden stores, `references/values-and-appset.md` for value loading) and `/helm-bjw-s-chart` (app-template values API). Plus **RESEARCH.md in this folder — read fully at run start** (facts below cite its sections; do not re-derive them).

## MCP grounding
Read-only only: `readonly-ai-gpu-kubernetes` (llama-swap pod/deployment facts, node allocatable), `global-searxng` + web fetch for residuals. No `admin-*`. No pod-exec anywhere — host/pod commands live in the runbook for the operator.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | containers/strata image (0.2.7 dual-flavor bundle + llama-swap supervisor) | M | 1 | [] | publishes the image interface (terminal/engine paths, entrypoint contract) — RESEARCH §1 |
| C02 | charts/strata internal engine pod (supervisor + run-config profile) | M | 1 | [] | independent of C01 given the frozen image interface — RESEARCH §2/§5 |
| C03 | gpu-ai wiring: appset entry + peers route on existing llama-swap + secrets | M | 2 | [C02] | peers entry names the rendered strata Service + inner model IDs — RESEARCH §3 |
| C05 | Strix-alone fallback (gfx1151 engine entry, STRIX_HALO seed) | M | 2 | [C01, C02, C03] | consumes the bundled second engine root (C01) + inner config schema (C02); appends its ID to C03's peers `models:` list (the file seam) — RESEARCH §7 |
| C04 | host-prep + enablement + validation runbooks (human-owned steps) | M | 3 | [C02, C03] | documents final names/gates incl. the on-target `--plan` fixups; written last |

## Wave order
1. C01, C02 (independent; run in id order)
2. C03, then C05 (both wave 2; C05 appends to C03's peers list — sequential in id order)
3. C04

## Human-owned steps (must ride the final report)
1. **Create Bitwarden item `strata`** (fields store, custom field `api_key`) and supply its UUID → replaces the `PENDING`-placeholder in `custom-values/gpu-ai/prod-values.yaml` (`strata-api-key`). Until then the strata pod strands on CreateContainerConfigError — quarantined by design (inner `apiKeys: []`, the peers entry points at a URL, not a secret).
2. Host prep per the C04 runbook: kernel/firmware (≠ linux-firmware 20251125), GRUB/sdbootutil cmdline `ttm.pages_limit=29360128 ttm.page_pool_size=29360128 amd_iommu=off`, BIOS UMA/ReBAR/ASPM, OCuLink x4 check, k3s `LimitNOFILE`/`LimitMEMLOCK` drop-ins (justified by open PR #2399 — no release self-raises, RESEARCH §2), on-target `rocminfo` → `ROCR_VISIBLE_DEVICES` values override.
3. **Pre-sync `--plan` gate (R1):** run `strata serve --profile <profile>.json --plan --output json` on the node and reconcile arena/expert-cache/conversation-cache numbers (and the C05 strix values) against the shipped profile before the first accepted request; first Strata request only when the trio is idle (RAM law).
4. PR creation/merge + ArgoCD sync + the one-attempt consented load/bench protocol (repo law: landing on main is user-owned).

## Risks / assumptions
- Node confirmed 128 GB RAM (R3); R9700 present with OCuLink x4 link is the card premise — step-0 runbook gates live enablement; missing/degraded link pivots to C05 Strix-alone (in scope per Q8).
- Engine pinned **0.2.7** with recorded digests (RESEARCH §1) — releases move fast (0.2.6 was two days before research); upgrades via renovate docker datasource + re-bench after every bump (0.2.4–0.2.6 had NO images — releases and tags are not in lockstep).
- Primary profile flags are verified against the PR #3636 fork configs (RESEARCH §5) — no longer a hypothesis list; the residual unknown is on-target `--plan` output sizing (C04 gate) and the unconfirmed IQ3_S pack size (RESEARCH §4).
- `ttl: 0` + lazy: first post-enablement Strata request takes minutes; a failed mid-pin leaves a half-pinned engine — startup-probe width + raised per-model `unloadTimeout` (C02) are the designed absorbs; inner unload is the escape (runbook).
- Shared models claim: IQ3_S needs ~135–160 GB under `/models/strata/` (GGUFs 83.6 GB + pack + MTP ~6 GB + headroom; RESEARCH §4) — the 500 Gi claim has room but the runbook checks capacity + the #1250 page-cache note; RWO multi-pod same-node mount assumed on local-path.
- Image build can't be proven until the branch is pushed (CI); `:main` + `pullPolicy: Always` is the documented new-container tag policy until the first `:v<run>` Renovate pin.

## Open questions — RESOLVED by research + ruling round (no new user round needed)
- O1 (peers naming): **resolved** — peers is `proxy` + explicit `models:` list (not a blanket proxy); outer rewrites FQ `<peer>/<id>` → bare inner ID on forward; unqualified ID routes while unshadowed; `/v1/messages` + SSE pass through (RESEARCH §3, contradiction #2). Wiring shape per C03.
- O2 (cold-load vs timeouts): **resolved** — outer per-peer `timeouts.responseHeader: 1800` ≈ inner `healthCheckTimeout: 1800`; `checkEndpoint: /health` on Strata is VALID (answers post-load, no key needed); `unloadTimeout` default 10 s would force-kill the ~47 GiB arena unload → inner raises it per-model (C02), grace 420 > unloadTimeout (RESEARCH §3).
- R1–R4 rulings folded into C02/C04/C05 + DECISIONS (strix seed = STRIX_HALO §5 + `--plan` gate; vision OFF documented toggle; 128 GB sizing math; `--kv-grow` deferred to a values toggle with the #1128/STRATA_KV_GROW_HOLD-void rationale).
- Residuals (runbook/research-gated, not blocking): C05 final strix expert-cache/resident-budget numbers (R1 gate); IQ3_S pack on-disk size (RESEARCH §4 unconfirmed); gfx1201 engine binary filename inside the package (C01 reads it at build — RESEARCH §1); 2026-10-21 perf table reproducibility (C04 acceptance).

## Research targets — closed ledger (see RESEARCH.md)
Answered: image facts → §1; `strata serve` CLI + profile JSON + flag validity → §2 (incl. `STRATA_KV_GROW_HOLD` VOID — documented env is `STRATA_KV_GROW=1`; `--api-key` not a serve flag; no nofile self-raise → wrapper stays); llama-swap peers/schema → §3; IQ3_S sizes → §4; PR #3636 configs verbatim → §5; TheRock/hipBLASLt 2B facts → §6 (gfx120X tarball exists 2.336 GB, no published sha; no gfx1201 table for hipBLASLt 100401 — 2B runs plain or self-tunes); STRIX_HALO §5 eight-set → §7. Genuine open residuals listed above ride as C04 on-target gates.

## On-target [VERIFY] items → C04 runbook (human-owned, NOT research, NOT repo)
Kernel/firmware versions + Tumbleweed package names, GRUB/sdbootutil cmdline (`ttm.pages_limit=29360128 ttm.page_pool_size=29360128 amd_iommu=off`), BIOS UMA/ReBAR/ASPM, OCuLink `lspci -vv` 16GT/s x4, `ROCR_VISIBLE_DEVICES` index via `rocminfo`, render/video numeric GIDs, SELinux-vs-AppArmor, k3s systemd drop-ins, THP (#771), in-container ulimits, `--plan` output reconciliation (R1 — incl. C05 numbers), timed manual unload proving `unloadTimeout`, bench reproduction within ~10% of PR #3636's one-at-a-time column (RESEARCH §5 headline numbers supersede the card's table — the acceptance run cites RESEARCH, one-attempt consented protocol inherited from the flash-next OOM ticket).
