# PLAN: gpu-ai flash-next Vulkan device-lost — fix the GTT-pinned load regime (branch A)
feature: 2026/2026-10-debug-flash-next-vulkan-oom
run-tag: openrouter-qwen3-8-flash
status: complete (2026-10-26 — FINAL whole-plan review APPROVED; see "Final review" below and STATE.json `plan_status`)
revised: 2026-10-26 (post-research reintegration pass — RESEARCH.md folded in; supersedes the initial placeholder plan of the same file)

## Goal
Restore `qwen3.8-flash-next-q3` (and the rest of the flash-next ladder) to a loadable regime on gpu-ai (Framework A6, Ryzen AI MAX+ 395 / gfx1151, 127.3 GiB unified RAM) by replacing the GTT-pinned `--load-mode none` placement with `--load-mode mmap` + `--fit off` (±`--no-host`), MTP off for the first controlled load — or, if that regime provably fails after the escalation ladder, land the evidenced "stock b11810 regime verdict" with the C02 fail-fast as the permanent state.

## Root cause (established — RESEARCH.md §TL;DR, Q1, Q4)
`--load-mode none` + `-ot "\.ffn_.*_exps\.=CPU"` on a RADV APU routes the "CPU" expert weights into **`Vulkan_Host` buffers = GTT-domain allocations**: pinned physical RAM, all competing for the driver's GTT budget (~½ RAM ≈ 63 GiB default [14][15]). The 83.8 GiB model needs ≈70–85 GiB GTT → kernel `amdgpu_vm_validate()` ENOMEM → `radv/amdgpu: Not enough memory for command submission` → device-lost mid-`load_tensors` (~21 s in) [35][40][27][23]. Upstream placement is **unfixed at b11810** (#29455 open, bisect-confirmed). The 32 GiB rungs live because their GTT demand stays under the same budget — same mechanism, different size. The `fused top-k mask` warning is a **confirmed perf-only red herring** [32][34][47][53]. `/api/hardware`'s "512 MiB dedicated" is the BIOS UMA carve-out; the GTT boot line is the real budget (§1.2). Community-proven fix on identical silicon: `mmap` (reclaimable file-backed CPU_Mapped, no GTT pin) + `--fit off` (skip the GTT-mis-accounting dry-loads) — several owners serve 86–111 GB flash-next GGUFs on 128 GB Strix boxes [40][47][42][48][53].

## Out of scope
- The 8 GiB dGPU `gpu` box (flash-next rungs echo there).
- Host kernel-param changes *executed by agents* — branch B is a user-owned node change; the plan records preconditions and verifies after (see C03/B).
- ROCm/HIP or Strix-fork images unless the A→(A+B)→C1 ladder fails — that becomes a **new ticket** (L-size, `containers/` per container-creation), not a C03 scope-explosion.
- Serving *throughput* optimization (forks/requant/PLE-split) — this ticket's bar is load + serve correctly.
- The llama-swap detector-version oddity (`v265` from a `-266` pod) — C01 notes it; separate chore if real.

## Chunk narrative (decision-critical points)
- **C01 (evidence, wave 1):** now includes the **zero-repro check** (RESEARCH open-q 2: the historical crash log's `load_tensors:` Vulkan_Host vs CPU_Mapped buffer lines already on the box close the mechanism question without another attempt) plus the six must-measure items: GTT default (dmesg `… of GTT memory ready` + `/sys/module/ttm/parameters/pages_limit`), `amdgpu.lockup_timeout` value, pod-bundled Mesa/RADV version, ik-llama-server presence+commit in `unified-vulkan-266`, UD-Q3_K_XL tensor-name dump (`-ot` regex match vs `per_layer_token_embd.weight`), and the unsloth `mtp-Qwen3.8-Flash-Next-Q8_0` **hc-layout check** (post-#28901 or a later `--spec-type draft-mtp` re-enable will hard-fail `check_tensor_dims: tensor 'output_hc_norm.weight' not found` [54][55]).
- **C02 (containment, wave 1, operator decision):** fail-fast the five rungs now, or debug live. If contained, C03 un-disables **q3 only** as the test rung; q4/q5/q6/orca stay disabled until q3 passes C04.
- **C03 (fix, wave 2, now concrete):** branch **A primary** — flash-next-family regime change (mmap, `--fit off`, MTP/draft removed first cut; `--no-host` evaluated), applied at **family level in the chart catalog** but *without* touching `${moe}` (shared by q35/q36/ornith/122b — blast-radius rule). **B contingency** only if C01's measured GTT budget can't hold the mmap-regime device+KV demand (~25–30 GiB estimate): user applies `ttm.pages_limit=32505856` (124 GiB, community standard [13][42][45]); hard rule **never pair B with `--load-mode none`** [23]. **C escalation** with cheapest tests first: C1 ik rung (presence-gated, low confidence [1–4]), C2/C3 off-cluster toolbox/fork proof → new ticket. **D struck** — research pre-empted it: "cannot run today" would be a *regime* verdict, not hardware; D survives only as the last-resort dated statement if A/B/C1 all fail to load.
- **C04 (verify, wave 3):** one consented load attempt per the freeze protocol; journal-clean grep widened to `amdgpu_vm_validate|BO_VA|command submission|ring .* timeout` (§1.1 arbiter + the separate ring-timeout DeviceLost class); serve smoke; a **second gate** to re-add MTP only if C01's hc-layout check passed; runtime-cliff mitigations (`GGML_VK_MAX_NODES_PER_SUBMIT=1` env, `-ub 512` [22][52][20][36]) if serving hits the prefill cliff.

## Commands (validation — repo convention: no unit suite except the chart pytest contract)
- test: `pytest charts/llama-swap/tests -v` (chart config contract; goldens move only via the agent-test session)
- lint: `helm dependency update charts/llama-swap && helm lint charts/llama-swap`
- render: `helm template llama-swap charts/llama-swap --set domain=spencerslab.com --set clusterName=gpu-ai`
- umbrellas: `helm lint services/gpu-ai/prod && helm template gpu-ai services/gpu-ai/prod --set domain=spencerslab.com --set clusterName=gpu-ai >/dev/null` (same for `services/gpu/prod`)
- config parity / blast radius: extract-and-render per TEST_SPEC §1; structural cmd-diff proving only flash-next-family IDs changed (all `${moe}`-consuming rungs and the gpu render byte-identical)
- GGUF tensor dumps (C01/C03 checks): `charts/llama-swap/scripts/gguf-py` reader against header range-fetches (C04-era precedent) or user-run inside the pod against the PVC copy
- cluster verify (readonly only): `readonly-ai-gpu-kubernetes`, `readonly-global-grafana` Loki (journal greps above), `GET /api/hardware|/running|/logs/stream/{model_id}`; pod/node exec commands are **presented to the user**
- flag-existence audit: `--fit`, `--no-host`, `--load-mode mmap` verified against llama.cpp@e3797b18 (b11810) `common/arg.cpp` before dev uses them (values.yaml audit list 2026-10-25 did not cover `--fit`)
- NOTE: `helm` absent in the agent worktree env — surfaces running these must install it or use a helm-equipped checkout.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Evidence: zero-repro buffer split + GTT/Mesa/ik/tensor/MTP-layout measurements | S | 1 | [] | — |
| C02 | Containment: fail-fast the flash-next ladder on gpu-ai (operator: now vs debug-live) | S | 1 | [] | independent; q3 re-enabled later by C03 as the test rung |
| C03 | Fix: flash-next family regime → `--load-mode mmap` + `--fit off`, MTP off first cut (+ B contingency, C escalation ladder) | M | 2 | [C01] | B-vs-A-alone decision and `--no-host` call consume C01's measured GTT budget; C1 is presence-gated by C01 |
| C04 | Cluster verification: consented load attempt, journal-clean proof, serve smoke, MTP re-add gate | S | 3 | [C02, C03] | validates the landed regime after user merge; consistent with whichever containment state C02 chose |

## Wave order
1. C01, C02 (independent; C02 gated on the operator's containment decision at approval)
2. C03 (concrete; no longer research-gated)
3. C04

## Operator decision points (at approval)
1. **C02 now vs debug-live** — containment trades a routable-but-refusing rung for safety while C01/C03 land; research says the freeze risk comes from *pinned-regime loads*, which the A regime removes, so debug-live is defensible if C04's one-attempt protocol is honored.
2. **Branch B authorization** (host `ttm.pages_limit`) — only if C01 measures a GTT budget below the mmap-regime requirement; user-owned node change + reboot; kubelet allocatable recheck after.
3. **MTP re-enable** — second consented step in C04, only if the unsloth sidecar passes the hc-layout check.

## Risks / assumptions
- GTT pages are **pinned physical RAM**; on a 127.3 GiB node with ~2 GiB swap, a pinned regime OOMs the kernel, not just the process (MiniMax proof [23]) — hence mmap-first, aperture-second, and the one-attempt freeze protocol.
- Kernel 7.3 may size GTT "more generously" than ½-RAM [24] — unquantified; C01's dmesg read settles it (contradiction #7).
- `--fit off` / `--no-host` semantics assumed present in b11810 — verify in the Commands flag-audit before dev.
- Post-load cliffs are a *different class* (ring-timeout DeviceLost at long prefill [36][20][52], deprecated MTP sidecar [54][55]) — C03/C04 pre-empt via MTP-off-first, ub/nodes-per-submit mitigations; they don't block the load fix.
- Golden configs in `charts/llama-swap/tests/golden/` predate the flash-next catalog; the test session re-captures as part of C02/C03 contracts.
- Landing is user-owned (PR only); chart `version:` untouched (release.yaml bumps), image pins untouched (renovate-owned).

## Final review (2026-10-26)

**Verdict: APPROVED — plan complete on the branch** (zero blockers/majors/minors; the full FINAL REVIEW block is in `chunks/C04.md` — read it, this section is the ledger summary, not a copy).

- Fresh tallies (whole-plan re-run, merge-base `60078f12c`…HEAD): `pytest charts/llama-swap/tests -q -rs` => **173/0/2** (both skips loud + named); `RUN_FLAG_AUDIT=1` => **174/0/1** (b11810 arg.cpp genuinely fetched); `RUN_HF_CHECK=1` => gate-2 `-hfd` sidecar **live-resolves**; chart + both-umbrella lint/template => rc=0 (pre-existing OVERRIDE_VIA_APPSET warnings only); `aislop ci --changes` => **0 errors / 0 warnings**.
- Joint C03+C04 final render (gpu-ai): all **5 flash-next rungs = `--load-mode mmap` + `--fit off` + `--spec-type draft-mtp` + `--spec-draft-n-max 2`** (orca-q6 spec-only, no `-hfd`); `${moe}` byte-frozen; gpu render cmd-unchanged (only the §8.4-exempted `, MTP` display marker); zero non-FN load-mode flips.
- Goal met and proven live: the mmap regime loads and serves flash-next-q3 on gpu-ai (EVIDENCE §13.2–6); AC1 carries the accepted substitute proof chain (C04 review minor-1 revision).

**Remaining chain — fully user-owned, fenced by repo law (no agent-executable work hidden behind it):** open/merge the ticket branch PR → ArgoCD syncs gpu-ai → **second consented MTP-enabled load per EVIDENCE §13.7** (one-attempt freeze protocol, journal watch, trio eviction accepted) → **q4 testable-next decision per EVIDENCE §13.5**. Open FRICTION items carry to the post-completion friction round (coord).
