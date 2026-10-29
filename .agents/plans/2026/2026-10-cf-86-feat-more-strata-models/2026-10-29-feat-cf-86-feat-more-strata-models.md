# PLAN: More models for Strata (card #86)
feature: 2026/2026-10-cf-86-feat-more-strata-models

## Goal
Widen the gpu-ai model roster where the node's RAM law allows it: add fit-tested Strata rungs (Coder IQ1_M coding rung, an abliterated/uncensored IQ3_XXS-class rung) as alternatives in the Strata pod's inner llama-swap, add heretic-style coding ablations of flash-next and 27B to the llama.cpp catalog, and make every new *and already-served-but-unrouted* model agent-routable via `.opencode/opencode.jsonc` with correct context limits. RESEARCH.md governs feasibility: Strata swaps per-profile (no live swap), only ≤~50 GiB-arena rungs fit, flash-next Q4-on-Strata and Ornith-122B-on-Strata are ruled out.

## Out of scope
- Any Strata profile ≥ UD-IQ4_XS experts class (arena fails the 125 GiB node — RESEARCH Q2/Q4).
- Ornith-1.5-122B **on Strata** (upstream #3574 closed "add later", #4460 open) — stays llama.cpp-only; watch item, not work.
- Re-serving qwen3.8-27b-q4/q6, flash-next-q4, ornith-1.5-122b rungs on llama.cpp — all already served and enabled ([repo] gpu-ai enablement + models overrides); only *routing entries* are missing (C05).
- qwen3.6-35B-A3B as a Strata profile (duplicates the served llama.cpp rung; best-guess decline — Open question Q4).
- New services, charts, ApplicationSets, secrets, container rebuilds (unless the C02 fallback path trips — see Risks).

## Commands
Repo validation, not unit tests (AGENTS.md "Pipeline specifics"). Export PATH first: `export PATH=$HOME/.local/bin:$PATH` (without helm on PATH pytest mass-skips its guarded tests).
- chart: `helm lint charts/llama-swap && helm template charts/llama-swap --debug >/dev/null`
- service render (extract-and-render, TEST_SPEC §1 pattern): `python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpuai-vals.yaml','w'))" && helm template llama-swap charts/llama-swap -f /tmp/gpuai-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai >/dev/null`
- suite (per-directory, basenames duplicate across chart suites): `python3 -m pytest charts/llama-swap/tests -q` — green means the chunk's new test files pass AND pre-existing ones (parity/schema/strata/off-parity/untouched) still pass; golden + `tests/evidence/strata-peers-expected.yaml` re-pins are the **test author's** property (dev never edits them).
- catalog: `python3 -c "import re,json; json.loads(re.sub(r'^\s*//.*$','',open('.opencode/opencode.jsonc').read(),flags=re.M))"` plus presence greps of every new/hygiene model id under the gpu-ai provider `models` map.
- trio cross-surface grep per new inner Strata id (chart `strata.config.models` + service `peers.strata.models` + provider catalog): `grep -rn "<id>" charts/llama-swap/values.yaml services/gpu-ai/prod/values.yaml .opencode/opencode.jsonc` — must hit all three (peers list intentionally lists inner ids one per line).
- container (only if C02 falls back to a manual-pack init): `docker build => no-daemon, CI-deferred` (docker-build.yaml on the pushed branch is authoritative — the designed passing shape, cf-77 ruling).
- quality gate: `npx aislop ci --changes`.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Coder IQ1_M as a Strata coding rung | M | 1 | [] | first new inner profile: establishes the profile-file/matrix/token pattern the later chunks extend |
| C02 | Abliterated/uncensored IQ3_XXS-class Strata rung | M | 2 | [C01] | edits the same template + matrix + service lines C01 just re-pinned; token-vs-manual-pack gate inherits C01's checkout-inspection evidence |
| C03 | flash-next heretic-2 Q4_K_M llama.cpp rung | M | 3 | [C02] | file-level serialization only: same chart-catalog families/matrix block + gpu-ai golden re-pin chain (one re-pin per wave, no branch conflicts) |
| C04 | 27B heretic Q4_K_M-MTP llama.cpp rung | M | 4 | [C03] | same serialization rationale as C03 |
| C05 | Provider-catalog entries + context sizes + Q4-default routing | M | 5 | [C01,C02,C03,C04] | needs the final exact served ids from all four; also carries the routing-default flip (Open Q6) and hygiene entries |

## Wave order
Strictly linear: 1. C01 → 2. C02 → 3. C03 → 4. C04 → 5. C05. C03/C04 are functionally independent of each other but touch the same `families:`/`matrix` regions and the same golden, so they chain to avoid merge conflicts; C05 is pure consumer and could theoretically run hygiene-only earlier, but keeping one final catalog commit honors "one plan of record, one catalog landing".

## Open questions (batched round — best guesses taken, plan proceeds on them)
1. **Coexist vs breadth (RESEARCH Q1):** true coexistence (≤~30 GiB arenas only) or catalog breadth with 3–6 min swaps? *Best guess:* breadth/time-share — add Coder + an IQ3_XXS-class rung as matrix alternatives with ttl 3600. *Impact if flipped:* C02 drops (only Coder survives); plan shrinks to C01+C03..C05.
2. **Uncensored Strata rung wanted? (RESEARCH Q2)** *Best guess:* yes, via SC117's public GSQ-RCO-abliterated ISTA set (exact installer-validated sizes, ungated) — rejected: orcarouter IQ3_XXS manual pack (gated HF_TOKEN passthrough would re-introduce the secret chain the keyless C-A ruling deleted). *Impact if declined:* C02 deleted; if the user wants orcarouter specifically, C02 grows an init-container capability + CI-deferred container build.
3. **Coder trade accepted? (RESEARCH Q3)** — ~91% of full on SWE-Verified, weaker general/multilingual. *Best guess:* accept as a dedicated coding profile. *Impact if declined:* C02 becomes the only new Strata rung; catalog keeps one entry less.
4. **qwen3.6-35B-A3B on Strata? (RESEARCH Q4)** — fast, coexists, but duplicates the served llama.cpp rung. *Best guess:* decline. *Impact if yes:* +1 profile in C02's shape (qwen36 family token), +1 catalog entry in C05.
5. **Catalog hygiene in cf-86? (RESEARCH Q5)** — ornith ladder + `qwen3.8-flash-next-orca-q6` are served but unroutable. *Best guess:* in scope (the card explicitly asks to update opencode.jsonc). *Impact if separate card:* C05 loses the hygiene bullet only.
6. **Where does "Q4 default" land? (card's make-Q4-the-default ask)** — Strata Q4 fails the arena (RESEARCH ruling 2). *Best guess:* the *routing* default moves to the llama.cpp `qwen3.8-flash-next-q4` rung in `.opencode/opencode.jsonc`-adjacent config, and the Strata profile stays IQ3_S. NOTE: the agent-route default itself lives in the `.rulesync` pipeline-models skill (cf-83 set it to `gpu-ai/qwen3.8-flash-next-strata`) — flipping it touches rulesync sources + generated mirrors. *Impact:* if the user means the pipeline model default, add a small rulesync re-route task to C05 (cf-83 C01 pattern); if they mean only "Q4 must be present+selectable", it's already true and C05 is verification-only.
7. **Slug confirm** (minted this run): keep `cf-86-feat-more-strata-models`. *Impact if replaced:* folder/worktree/branch renames before any dev lands.

## Risks / assumptions
- **New-profile run-config seeds are analogous, not yet on-target-generated.** The profile ConfigMap seeds (paths under `Strata-data/models/<MODEL>/…`) are derived from the measured iq3_s layout; the checkout's setup writes its own JSON on the claim and the on-target `strata serve --plan` verification stays **human-owned** (cf-77 C04 runbook discipline). A wrong seed path is exactly the crash class cf-77 recorded — chunk ACs pin render-shape only, not on-target serving.
- **C02 has a gate:** if the pinned checkout's setup catalog carries no abliterated entry (verify via `./setup.sh --help` inventory recorded on the claim), the fallback is an ORCA.md-style manual pack (init-container capability + container surface, CI-deferred build). Dev must escalate NEEDS_INFO at the gate, not improvise.
- **Residency math:** each new swap rung holds ttl 3600 + unloadTimeout 180; the 96Gi cgroup and `--memory-limit-mib 92160` stay valid for all planned rungs (largest new arena ~49.8 GiB < 50 GiB IQ3_S). No matrix set may co-load two arena models — suite pins this.
- **Inner aliases stay unique** inside the inner llama-swap (engineProfile `aliases`/`model_name` of new profiles must not shadow `qwen3.8-flash-next`).
- Label-drift surface: this run's pipeline set (`Context`) comes from the card's `Pipeline: Context` board label — recorded on the card, not in these files (board convention).
- Stale chart comment "180B-class" (flash-next descBase) is a known contradiction (RESEARCH cautions) — fix rides C03's family-block touch if trivial, else leave.
- Provider-catalog context values: all new Strata/llama.cpp rungs are 262144-class (`--max-context 262144` / `-c 262144`); no 1M variants added.
