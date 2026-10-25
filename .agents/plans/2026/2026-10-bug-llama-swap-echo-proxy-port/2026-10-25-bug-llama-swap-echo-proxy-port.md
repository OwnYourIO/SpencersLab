# PLAN: llama-swap echo proxy ${PORT} crash-loop + immutable image pin
feature: 2026/2026-10-bug-llama-swap-echo-proxy-port
Fast lane (production gpu box down) — kickoff compressed, see STATE.json.

## Goal
Fix the llama-swap crash-loop on the gpu box: the declared-half renderer injects
`proxy: http://localhost:${PORT}` UNCONDITIONALLY
(`charts/llama-swap/templates/_helpers-llama-swap.tpl:100-103`), and llama-swap's
macros.go hard-fails config load when proxy contains `${PORT}` but cmd does not
(verified identical in the official v262–v266 source tarballs,
`/tmp/opencode/ls266/*/internal/config/macros.go:183`). Every fail-fast echo
entry trips this (gpu: 24 echoes). Second, replace the image pin
`ghcr.io/mostlygeek/llama-swap:unified-vulkan-262` — proven content-mutable:
the tag was rebuilt upstream and the new content carried the validator into
production — with a verifiable, renovate-managed immutable pin (user-ruled
2026-10-25: proper pin IN THIS TICKET).

## Out of scope
- flash-next-q3 fit work (separate live investigation).
- Echo CONTENT changes — echo cmd strings stay byte-exact (P3 bar, golden-pinned).
- Chart `version:` bumps — release.yaml owns those (C03 touches `appVersion:`
  only, as image-pin metadata).
- preload/matrix/hooks changes; no edits to the sibling ticket folder.
- Post-merge cluster work — redeploy/re-sync is user-owned (ArgoCD).

## Incident evidence (coord-investigated 2026-10-25; no re-research)
- Deploying the catalog ticket (2026/2026-10-feat-llama-swap-config-generation,
  now on main) left llama-swap crash-looping on gpu:
  `failed to load config ... model ornith-1.5-122b-q3: proxy uses ${PORT} but
  cmd does not - ${PORT} is only available when used in cmd`.
- Render state verified on main @90e660569 (this session): gpu renders 58
  models = 34 live + 24 echoes, ALL 24 echoes carry `proxy:
  http://localhost:${PORT}` (CM sha c3a8e3297c89...); gpu-ai renders 58 live /
  0 echoes (CM sha 9f359249cee7...); default (chart values only) renders 58
  echoes (full-catalog default-disabled, CA2), all with proxy.
- macros.go semantics (the check runs AFTER user-macro expansion —
  `mergeModelMacros` + `substituteMacroList` precede the `${PORT}` test):
  live composed cmds carry `${server-cmd}` (macro value holds `--port ${PORT}`),
  whisper/rana raw cmds carry literal `--port ${PORT}`, echo cmds carry no
  `${PORT}` at all → only echoes violate.
- The shape is INHERITED: the golden gpu.config.yaml (pre-ticket capture) has
  `proxy: ${PORT}` on its 6 disabled echoes and booted fine for weeks — the
  node previously ran image content WITHOUT the check. Old config was a
  landmine; our deploy stepped on it; both falsified assumptions are recorded
  in DECISIONS.md.
- Registry enumeration (ghcr.io token + tags/list, paginated; 2026-10-25):
  release-versioned unified tags exist 256…266; latest release tag
  `unified-vulkan-266`, manifest digest
  `sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045`.
  Current `unified-vulkan-262` resolution (the drifted rebuild):
  `sha256:038bb09388681895e9d51e5cf02aaa38178cd6571273cd73b7df2712c416b48d`.
  Vulkan unified builds bake the LATEST ggml-org/llama.cpp RELEASE TAG at
  build time (docker/build-image.sh in the v266 tarball) — the new pin's
  llama.cpp rev needs the flag re-audit (C03 task, STOP-gated).
- renovate.json verified: NO manager tracks this image today (the "Plain
  image:" manager matches `image: name:tag` in templates only; the
  app-template `repository:`/`tag:` split in values.yaml matches nothing).
- Suite baseline on main @90e660569 VERIFIED this session: **1 failed / 118
  passed / 1 skipped** — `test_render.py::test_gpu_ai_tools_container_enabled_with_token`
  pins `python:3.12.15-slim-bookworm`, out-dated by renovate bump `dbaaadced`
  (values carry `python:3.15.1-slim-bookworm`). The kickoff premise of
  0f/119p/1s is superseded by this verified baseline; C01 owns the fix via the
  TEST_SPEC §7 amendment discipline.

## Commands
- test: `PATH=/tmp/opencode/bin:$PATH python3 -m pytest charts/llama-swap/tests -v`
  (helm v3.16.4 at /tmp/opencode/bin; `helm dependency update charts/llama-swap`
  first if charts/app-template-5.0.1.tgz is missing — probe before rebuilding,
  FRICTION)
- lint: `helm lint --strict charts/llama-swap`
- renders x3: `helm template llama-swap charts/llama-swap [-f <service values>]
  --set domain=spencerslab.com --set clusterName=<default|gpu|gpu-ai>
  --show-only templates/configmap-llama-swap.yaml` (service values extracted per
  TEST_SPEC §1 pattern)
- CM diff audit (C02): gpu-ai CM data sha256 UNCHANGED (9f359249cee7...);
  gpu CM diff vs pre-fix render == exactly the 24 `proxy:` lines removed on the
  echo set, nothing else; default render: 58 proxy lines removed.
- gates: `RUN_HF_CHECK=1` leg stays green (1 skipped without the gate).
- quality: `aislop scan charts/llama-swap` (directory-scoped — `--changes`
  scopes 0 files on an unpushed worktree branch, FRICTION).
- renovate (C03): global-renovate MCP `check_setup` → `test_package_rules` →
  `validate_config` → `lint_config` against this repo.

Expected suite bars (honest recount from the VERIFIED baseline; recommended
case granularity — the test session owns final granularity and pins exact
digits in TEST_SPEC, §7 chain discipline):
- baseline: 1f / 118p / 1s
- C01 handoff: 3f / 121p / 1s — reds: invariant[default], invariant[gpu],
  proxy-absent[gpu]; greens gained: stale-test fix, invariant[gpu-ai],
  proxy-absent[gpu-ai]
- C02 complete: 0f / 124p / 1s
Invariants the arithmetic must satisfy: verified baseline above, zero new
skips, and C02-done == 0 failures.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | test contract: boot-safety invariant + parity re-expression + stale-test amendment | M | 1 | [] | immutable-tests rule: the contract is written and proven RED before any fix |
| C02 | renderer: emit proxy only when the final cmd carries ${PORT} | M | 2 | [C01] | the fix must satisfy C01's red contract |
| C03 | image pin: unified-vulkan-266 (verifiable) + renovate tracking | M | 2 | [C01] | suite baseline defined by C01; files independent of C02 — run in id order after C02 for one unambiguous green bar |

## Wave order
1. C01 — executed ONLY by this ticket's agent-test session (immutable-tests rule).
2. C02 then C03 — both dev. File sets are independent (_helpers tpl vs
   values.yaml/Chart.yaml/renovate.json); id order keeps the suite bar readable
   (C02 flips the C01 reds green; C03 then re-runs the now-green suite).

## C05 linkage (sibling ticket)
`charts/llama-swap/tests/evidence/c05_expected_evidence.yaml` (sibling ticket
2026-10-feat-llama-swap-config-generation) expects a clean gpu boot with 58
registered models (34 live + 24 echoes) — the post-fix gpu boot of THIS ticket
IS that observation. C05 execution (sibling ticket, post-merge) verifies this
fix live; this ticket makes no preload/matrix changes and writes nothing into
the sibling folder.

## Acceptance caveat
Post-merge redeploy is user-owned; this ticket cannot verify pod boot until the
PR lands and ArgoCD syncs. The pre-merge proof is the C01 invariant (a faithful
offline simulation of the deployed binary's macros.go port rule) plus the C02
render/sha audit.

## Risks / assumptions
- The invariant test must mirror macros.go faithfully: expansion of config-level
  macros overridden by entry-level `macros:` (no rendered entry has entry-level
  macros today; the simulation must still handle them).
- unified-vulkan-266's llama.cpp is newer than the audited 889edf43; a flag
  removal/regression upstream is a STOP (needs-research via RESULT), never a
  blind bump.
- Versioned unified tags have been rebuilt before (that is the incident); C03
  re-pulls the 266 manifest and compares against the digest recorded above —
  mismatch = STOP.
- If the user picks the alternative pin at approval (digest of the CURRENT
  unified-vulkan-262 resolution instead of the 266 tag), C03 reshapes per its
  Notes for dev; the flag-audit obligation degrades to needs-research (content
  provenance unknown without a docker daemon).