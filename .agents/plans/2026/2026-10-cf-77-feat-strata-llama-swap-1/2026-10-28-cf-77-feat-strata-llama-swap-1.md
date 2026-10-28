# PLAN: cf-77 run 2 — keyless Strata + consolidation into the llama-swap Application (in-chart)
feature: 2026/2026-10-cf-77-feat-strata-llama-swap-1
run2of: cf-77-feat-strata-llama-swap (first run plan-complete, merged at 1b1f6d5d0; its folder is frozen history + read source)

## Goal
Two user-ruled finishing touches on the merged cf-77 deliverables. **C-A Keyless Strata**: `api_key: "none"` becomes the shipped default and the ENTIRE strata secret chain comes out (ExternalSecret template, bitwardenIds sentinel + PENDING custom-values entry, `${env.STRATA_API_KEY}` fail-fast env + strand design, runbook Bitwarden human-step, README rung-6). **C-B Same app, separate pod**: the standalone `gpu-ai-strata` Application disappears — the strata pod becomes a SECOND app-template CONTROLLER inside `charts/llama-swap`, so one ArgoCD Application (`gpu-ai-llama-swap`) owns both pods while the strata pod keeps its distinct Deployment/Service/pod shape (privileged+hostPath, Recreate, 420>180+30, shared claim, `(p|s)` matrix, peers routing).

Out of scope: engine/container changes (containers/strata untouched), the peers MECHANISM (shape unchanged), split mode (still deferred), and — by the Q-C ruling — **`.github/workflows/release.yaml` gets NO edits** (plus: no `.gitignore` edit, no Chart.yaml/Chart.lock change on the parent).

## Architecture decision (final; the Q-C ruling eliminated every subchart variant)
**In-chart second controller.** Re-weighed under "no release.yaml edits + delete charts/strata" and prototype-verified (2026-10-28): the vendored-subchart candidates all fail — loose-undeclared dir trips `helm lint` ("metadata is missing these dependencies") and hides under `.gitignore` `charts/**/charts`; declared-with-empty-repo and declared-with-file:// both make `helm dependency list` emit a line whose repo column the UNTOUCHED release.yaml awk loop mis-splits (empty fields collapse → `$3` = status text) → `helm repo add strata unpacked` → step exit 1 under Actions `bash -e` → every future release job breaks. The in-chart shape sidesteps all of it: **Chart.yaml, Chart.lock, .gitignore, release.yaml all pristine; dependency tooling never sees strata.**
Verified mechanics the chunks implement:
- **Default-OFF = seven native data flags, flipped together, from gpu-ai service values**: `app-template.controllers.strata.enabled` + `app-template.service.strata.enabled` + `app-template.persistence.{strata-config,strata-profile,strata-kfd,strata-dri,strata-shm}.enabled` (chart defaults `false`). Persistence entries carry flags because an advancedMounts into a DISABLED controller HARD-FAILS the render. OFF-state parent render is **byte-identical to today's baseline** (diffed in prototype).
- Consolidated objects: strata Deployment+Service = **`gpu-ai-llama-swap-strata`** (app-template fullname + controller-key suffix) — the peers evidence URL flips to it; single tree SA (`gpu-ai-llama-swap`) — strata's run-1 own SA simply ceases (Q-A "Drop" achieved structurally, `automountServiceAccountToken: false` unchanged).
- Pod-shape keys (grace 420, supplementalGroups, seccomp Unconfined) ride `controllers.strata.pod.…` per-controller — `defaultPodOptions` is tree-global and would diff the main pod.
- **Mount-exactness (golden law):** run-1's `config`/`tools` persistence entries are `globalMounts` = they attach to EVERY enabled controller, which would collide `/app/config` on the strata container. Both re-key to `advancedMounts` enumerating their CURRENT consumers exactly (config → `llama-swap.main` + `llama-swap.tools`; tools → `llama-swap.tools` readOnly + main keeps today's tools mount — reproducing per-container volumeMount sets byte-for-byte, no "improvements"); `models` STAYS globalMounts (strata legitimately shares `/models`, Q3 claim unchanged).
- Raw templates (inner-config ConfigMap + profile ConfigMap + NOTES section) move into `charts/llama-swap/templates/`, each gated whole-file on `{{- if (index .Values.app-template.controllers.strata "enabled") }}` (the `index` form is mandatory — dotted access through the hyphenated key is a Go-template lexer error, verified).

## Commands
- `helm lint charts/llama-swap && helm template charts/llama-swap --debug` (default-OFF state)
- **OFF parity**: `diff <(helm template gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com) <(git show <base>:…) `-style comparison against the PRE-TICKET render — byte-identical (the parent golden suite enforces the same invariant)
- ON render (all seven flags true): object set gains exactly Deployment+Service `gpu-ai-llama-swap-strata` + ConfigMaps `strata-config`/`strata-profile`; zero `ExternalSecret`/`strata-api-key`/`STRATA_API_KEY` anywhere; main+tools containers' `volumeMounts` byte-identical to the OFF render; strata container mounts exactly `[/app/config, /models, /dev/dri, /dev/kfd, /dev/shm, /profile]`
- subset-flag guard: any PARTIAL set of the seven flags fails the render loudly (expected error names the missing identifier)
- `python3 -m pytest charts/llama-swap/tests/ -q` (single suite dir after the test re-home; per-directory rule)
- wiring greps: `grep -n "strata" services/gpu-ai/prod/values.yaml` → no `charts: strata` entry; the seven flags + inner config live under the `llama-swap:` block; peers proxy == `http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080` (exact, matches re-authored evidence); `grep -rn "strata-api-key\|PENDING-OPERATOR\|OVERRIDE_VIA_CUSTOM_VALUES.*strata" services/ custom-values/ charts/` = zero; `test ! -d charts/strata`
- untouched-by-design checks: `git diff --stat` shows NO changes under `.github/`, `.gitignore`, `charts/llama-swap/Chart.yaml`, `charts/llama-swap/Chart.lock`
- render of gpu box values (`services/gpu/prod` llama-swap block): identical to baseline (no flags there)

## Skills (later agents MUST load)
`/helm-bjw-s-chart` (controllers/persistence/advancedMounts keys, `enabled` semantics) + `/helm-chart-creation` (+ `references/values-and-appset.md`) + `/llama-swap` (peers). First-run folder RESEARCH.md + DECISIONS.md = read sources (cite, never edit). `/container-creation` not needed (no container work).

## MCP grounding
`readonly-ai-gpu-kubernetes` only (inspect live `gpu-ai-strata` + `gpu-ai-llama-swap` state pre/post — read-only). No `admin-*`, no pod-exec.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | charts/llama-swap absorbs strata: in-chart controller + moved gated templates + keyless + mount re-keys | M | 1 | [] | — |
| C02 | delete `charts/strata/` (dir fully re-homed by C01 + test re-home) + 3 pointer-prose rewords in containers/strata (image untouched) | S | 2 | [C01] | deletion is safe only after the content lands in the parent |
| C03 | gpu-ai service values: appset entry out, flags + config nested into `llama-swap:` block, peers URL, custom-values extraction | M | 2 | [C01] | flag/config paths must match C01's landed chart shape (not C02 — the grep-level absence of the dir is asserted by tests regardless of C02 order) |
| C04 | docs: runbook keyless + swap sequencing; chart-README re-home into charts/llama-swap/README.md | S | 3 | [C01, C03] | documents the final landed shape; last |

## Wave order
1. C01
2. C02, C03 (independent; run in id order)
3. C04

## Test-authority brief (single agent-test session, BEFORE dev, one pass; dev NEVER touches `charts/llama-swap/tests/**` / `evidence/**`)
Re-home + flips (files: old `charts/strata/tests/**` content re-homed into `charts/llama-swap/tests/`; `strata_testlib.py`; `test_config_parity.py::_assert_strata_peers`; `evidence/strata-peers-expected.yaml`; `test_runbook_completeness.py`):
1. testlib: chart dir → `charts/llama-swap`; RELEASE → `gpu-ai-llama-swap`; enable = the seven `app-template.…` flag paths (old two-flag shape invalid); old `bitwardenIds`/`--set enabled` mechanics die.
2. Secret chain → ABSENCE asserts everywhere (no ExternalSecret in any flag state, no STRATA_API_KEY, profiles pin `"api_key": "none"`).
3. NEW/OFF: default-render byte-parity vs parent golden (unchanged golden + peers-delta rule); ON render object-set + mount-exactness pins (main/tools volumeMount sets == OFF render; strata container's exact six paths); subset-flag loud-fail guard (divergence).
4. Wiring: `charts.strata` appset entry absent; flags nested under `llama-swap:`; zero sentinel/UUID greps; `charts/strata` dir absence asserted.
5. Peers evidence: proxy URL → `http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080` (models/timeouts/no-apiKey clauses UNCHANGED — run-1 evidence already pins the post-consolidation name shape).
6. Runbook completeness: drop `PENDING-OPERATOR-UUID`/Bitwarden/strand tokens; add keyless-confirm, swap-sequencing, `gpu-ai-llama-swap-strata` tokens (exact set = as C04 authors).
7. Untouched-by-design guard: test asserting `.github/workflows/release.yaml` + `.gitignore` have no strata-related deltas (cheap text assert; the Q-C ruling becomes machine-pinned).
Mechanical breakage → coord routes silently to the test session; functionality-changing NEEDS_INFO → user.

## Commands note
"Commands" above are the suite's shell equivalents; the pinned truth is the pytest suite.

## Human-owned steps (short)
1. Push → PR → user merges (CI = helm suites + aislop; no containers/** trigger). Landing on main user-owned per repo law.
2. First sync after merge (operator watch, minutes): ArgoCD prunes the `gpu-ai-strata` Application; `gpu-ai-llama-swap` re-renders (config ConfigMap delta → reloader restart of the main pod = accepted existing churn; strata pod comes up lazy, no secret prerequisite anymore). First Strata request only with the trio idle AND strata cold pre-swap (RAM law; runbook sequencing step). Seconds-level strata-route blip during the swap accepted (Q-B; llama.cpp surface never blips).
3. Keyless spot-check: port-forward the strata service → `/health` answers keyless; chat request for `qwen3.8-flash-next-strata` via `llama.<domain>` succeeds with no Authorization header.
4. Carried from run 1 (unchanged): host prep + `--plan` reconcile gates; manual bump ledger for strata image tags + closing cross-flavor-bleed renovate PRs.

## Risks / assumptions
- The in-chart controller bloats the (byte-frozen) parent values tree by ~200 lines of privileged-shape data — accepted as the cost of the single-Application ruling; the OFF-parity + golden tests make the risk machine-checked rather than trust-based.
- AdvancedMounts re-key changes mount ORDERING within a container's list (same set) — k8s-stable, but the golden suite compares rendered YAML: re-home golden regeneration belongs to the test session (it already owns parity baselines), never to dev.
- `controllers.strata.pod` must carry EVERY pod-level option run-1 kept in its own defaultPodOptions (grace, seccomp, supplementalGroups, hostIPC/PID/Network false-defaults) — a missed key silently inherits tree/global defaults; the ON-render object pins guard it.
- Prune-vs-create race: honored by the swap precondition (strata cold) — no double-pin window.
- Keyless posture: engine+inner+outer all unauthenticated in-cluster, mirroring the outer's existing `apiKeys: []` posture; no NetworkPolicy assumed.

## Open questions — ALL CLOSED (Q-A drop / Q-B one-sync blip accepted / Q-D toggles untouched, as planned; Q-C reshaped into this architecture by the user ruling — no new questions surfaced: every re-weigh input was answerable from repo + prototype evidence)
