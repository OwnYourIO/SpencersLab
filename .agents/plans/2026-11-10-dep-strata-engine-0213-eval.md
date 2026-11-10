# 2026-11-10 dep — GATED evaluation: Strata engine bump 0.2.9/0.1.55 → 0.2.13/0.1.59

**Status: NOT EXECUTED. This is an owner-commissioned evaluation plan. Every
step below is gated; the owner gate at the end is the only thing that may
authorize a pin change.** Commissioned 2026-11-10 after the q4 SystemOOM
crashloop envelope round, per the research file
`.agents/plans/2026-11-10-research-strata-q3-q4-rungs.md` (§2D, §6, §8.3 —
untracked in the main checkout; the owner lands it separately).

Current pin (containers/strata README ledger): image
`ghcr.io/niko1221/strata:0.2.9-rocm-gfx120x` + `-rocm-gfx1151`, engine
`0.1.55-linux-x86_64-hip-{rx9070,halo}`, source checkout `v0.2.9` +
`carry/ornith-q36.patch`. Candidate target: 0.2.13 / engine 0.1.59, released
2026-11-09 (both rocm flavors exist on GHCR; **0.2.10 has no container image**
— the image-gap law removes it from consideration).

## Why a bump is attractive

- **gfx12 perf wins land at 0.2.11+** (research §2D, source [16]): K-quant MMQ
  prompt kernels default-on (+10–17% prompts on an R9700), route-tail-skip
  default-on for unsloth files (+6.2% decode geomean on an R9700, with a
  measured KL cost of 0.077 teacher-forced / 0.203 agent-segment), and bare
  `--prefill auto` ceiling 32768 (the q4/orca flash-next profiles would gain
  32K prompt chunks for free — primary already pins `auto:32768`; ornith keeps
  its own q36 chunk rules).
- **0.2.13 specifically** adds PR #5531 (arena loads from file cache — the
  #5317/#5327 arena-RAM-check pathology class that afflicts 0.2.10–0.2.12)
  and `--ram-keep-gib` (arena admitted only if W GiB stay free after it — a
  future envelope lever; absent at 0.2.9).
- **v3.1 catalog rungs need engine ≥ 0.1.57** (`UNSLOTH_V31_ENGINE = (0,1,57)`
  in setup.py@v0.2.13): `UD-IQ3_XXS` (arena ≈46.9 GiB, same envelope as the
  IQ3_S flagship), `UD-Q3_K_XL` (≈52.3 GiB), `UD-IQ4_XS-v31` (≈56.25 GiB).
  A bump is the prerequisite for ever trialing them.

## Why it stays gated (OPEN gfx1201 crash-regression cluster)

All four are OPEN as of the 2026-11-10 research fetch; none names a fix in the
0.2.13 release body; 0.1.59 is unproven against every one of them:

- **#5559** — GPF storm in `libhsa-runtime64` on 0.1.58: 9 crashes in 5 h under
  35K–92K prompts, conv-heavy, parallel 2, on an R9700 + 128 GB RAM box — the
  nearest published twin of the ai-gpu node. 0.1.57 was clean on that box.
- **#5608** — repeatable AMDGPU gfxhub page faults during IQ3_S inference on
  **both 0.1.57 AND 0.1.58** (RX 9070 XT, CachyOS) — contradicts #5559's
  "0.1.57 clean", so gfx1201 stability is box-dependent.
- **#5635** — 0.1.58 load-time RAM regression 67.8 → 114.8 GB → systemd-oomd
  SIGKILL, reproducible with 117 GiB free (plus the `--no-tui` systemd
  breakage). A load-RAM regression is precisely the failure class of the
  2026-11-10 incident.
- **#5564** — 0.1.58 prefill stuck at ~111K tokens; cancel leaves busy-wait.

Research §7 ruling: treat **no** post-0.1.55 engine as proven on gfx1201. The
node-proven pin is 0.2.9/0.1.55; a bump is only defensible behind the ledger +
soak + `--plan` + re-bench law below.

## Steps (in order, each a gate)

1. **Re-check upstream state (read-only).** #5559 / #5608 / #5635 / #5564:
   closed? fix named in a 0.1.59+ release body? new gfx1201 reports since the
   2026-11-10 fetch? Record findings beside this plan before spending any build
   time. Any OPEN regression with a named engine fix re-orders the candidate.
2. **Branch-built image at 0.2.13, both flavor tags, per the ledger law**
   (containers/strata/README.md): one commit changes BOTH FROM tags
   (`0.2.13-rocm-gfx120x` + `0.2.13-rocm-gfx1151`) + the pin-ledger rows with
   re-read digests (anonymous token + manifest HEAD, recording each image's
   `com.strata.engine` OCI label as the engine-version proof), source stage tag
   `v0.2.13`, carry patch re-applied and re-verified (the #3574 constants are
   claim-compiled; ornith serves from no packaged root). Build on the branch —
   no main pin moves.
3. **Soak under #5559's traffic shape** on the branch image: 35K–92K prompts,
   `parallel 2`, conversation-heavy agent sessions (controller+worker
   histories), long enough to hit the conv-cache eviction path — i.e. also
   exercising #5697, whose `MALLOC_MMAP_THRESHOLD_=1048576` workaround ships
   in the chart env regardless of engine version. Watch: GPF/page-fault
   signatures in dmesg, load-peak RAM (#5635 shape), prefill stalls past ~100K
   (#5564 shape), parking refusals.
4. **On-node `--plan` re-checks per runbook §3.4** (`strata serve --plan
   --output json`, human-run — see Commands): engine label/version lines,
   arena fit, KV/slot sizing, PLE resolution mode, prompt-chunk lines. The
   2026-11-10 envelope values (cgroup 110Gi, q4 parallel 2 + concurrencyLimit
   1, malloc env) stay in force through the soak — a bump evaluation is not an
   envelope re-rule.
5. **Re-bench the prefill ladder** against the recorded bar: ≈2,519 tok/s
   @64–200K rung-4 (PR #3636 node class, strata-host-prep-gpu-ai.md §3.4a),
   plus the q4 decode band under agent traffic (40–60 tok/s measured
   2026-11-10) and the cold-pin time (71.73 GiB @ 4.90 GiB/s). Expected wins:
   K-quant MMQ +10–17% prompts, tail-skip +6.2% decode geomean (accept the
   measured KL cost as the price; re-check against the 0.077/0.203 figures).
6. **Owner gate.** Present: upstream state (step 1), soak evidence (steps
   3–4), bench deltas (step 5). Only an explicit owner ruling moves the pin on
   main; until then the branch image stays an experiment.

## Out of scope (explicit)

- **No routing change to any v3.1 rung** (`UD-IQ3_XXS` / `UD-Q3_K_XL` /
  `UD-IQ4_XS-v31`) without an on-node top-token yardstick run
  (`tools/quant_quality.py` class) — they carry zero published Strata
  yardsticks and zero single-R9700 Linux speed numbers (research §2B).
- No engram/PLE-table swap, no `--ram-keep-gib` adoption, no conv-cache or
  max-context re-rule — each is a separate owner-gated envelope decision.
- No change to the 2026-11-10 envelope repairs shipped on branch
  `fix-strata-q4-oom-envelope` — they hold on every engine version.

## Commands (validation for any bump commit, per repo recipe)

```
export PATH=$HOME/.local/bin:$PATH
helm lint charts/llama-swap
helm template charts/llama-swap > /dev/null
cd charts/llama-swap && python -m pytest tests/ -x -q
```

Human-run, never by an agent (no pod exec is granted to any agent tier):
the runbook §3.4 `--plan` reads — `kubectl exec -n default
<strata-pod> -c strata -- /opt/strata/terminal/bin/strata serve --plan
--output json` (exact pod/container per runbook §3.3) — and every soak/bench
session on the node.
