# PLAN: More models for Strata (card #86) — FINAL (post-answer round)
feature: 2026/2026-10-cf-86-feat-more-strata-models

## Goal
Widen the gpu-ai roster within the node's RAM law, per the answered batched round: two Strata ablation rungs (SC117 public GSQ-RCO-abliterated IQ3_XXS + orcarouter gated Uncensored IQ3_XXS manual pack) as time-shared inner-matrix alternatives, heretic-style coding ablations of flash-next and 27B on the llama.cpp side, and full provider-catalog routing in `.opencode/opencode.jsonc`. The user's two overrides (ornith-122B-Q4 and flash-next-Q4 "should fit / served from Strata") are NOT folded in as verdicts: an explicitly scheduled After-Planning research round re-verifies them; C06 carries both shapes behind that gate.

## Scope decisions from the batched round (U-rulings, full text in DECISIONS.md)
- U1 breadth-with-swaps: multi-profile Strata catalog stands, 3–6 min cold pins accepted.
- U2 BOTH ablated Strata rungs (SC117 + orcarouter); HF_TOKEN chain verified present on the llama.cpp side (AC-pinned in C02); gated-download mechanics for the Strata init are a research item (R-d).
- U3 Coder IQ1_M declined — the draft's Coder chunk is DELETED (see renumber map).
- U4 qwen3.6-35B-A3B on Strata declined (no duplicate).
- U5 OVERRIDE (VERIFICATION-PENDING): ornith ladder + flash-next-orca-q6 "served from Strata" + opencode.jsonc entries wanted — collides with RESEARCH's blocked rulings; re-verification is R-a/R-c, not a silent fold.
- U6 OVERRIDE (VERIFICATION-PENDING): flash-next Q4 "should fit. Double check." — re-derivation is R-b.
- U7 slug `cf-86-feat-more-strata-models` kept.

**Renumber map (draft → final):** old C01 (Coder) deleted; old C02→C01 (SC117); NEW C02 (orcarouter); old C03→C03; old C04→C04; old C05→C05; NEW C06 (research-gated). All pre-existing chunks were `pending`, so renumbering is contract-clean; nobody should chase draft ids after this commit.

## Scheduled stage: After-Planning research round (card's legacy Research checklist has After Planning checked)
Launched by coord as `agent-research` AFTER plan approval and BEFORE the test session writes C06's tests (C01, C03–C05 are unaffected and may already be in test/dev; C02 proceeds normally except its token-mechanics step consumes the R-d answer — unanswered R-d at C02 dev time ⇒ NEEDS_INFO, not improvisation). Its summary lands as an appended section in this folder's RESEARCH.md. Scope:
- **R-a Ornith-1.5-122B Q4 on Strata:** re-derive the arena math from primary sources; explicitly test whether the existing ruling conflated (i) page-locked arena fit, (ii) llama.cpp/llama-swap LOADER support, (iii) node RAM ceiling; which 122B Q4 GGUFs exist in Strata-validated packings; current state of upstream #3574/#4460 and the announced community optimization.
- **R-b flash-next Q4 on Strata:** which Q4 (unsloth UD-IQ4_XS 55 GiB experts vs UD-Q4_K_XL 72 GiB vs orcarouter IQ4_XS ~97.5 GB files); pin down what the "125 GiB" figure actually caps (node spendable RAM vs cgroup 96Gi vs `--memory-limit-mib 92160`) against the measured IQ3_S 46.84 GiB anchor; whether a Q4 profile fits with trimmed conversation-cache/KV and at what decode-ROI (documented −15% decode on R9700 at UD-Q4_K_XL).
- **R-c what "served from Strata" concretely requires today:** setup.sh catalog inventory for unsloth/ornith/orcarouter paths, upstream issue status at run date, GGUF file existence for Q4 rungs, manual-pack (ORCA.md-class) feasibility at Q4 sizes, models-PVC capacity math (500Gi claim vs +43–111 GB packs).
- **R-d gated-pack download for the Strata init:** does setup/manual path honor `HF_TOKEN` (huggingface_hub); may the init container consume the EXISTING `hf-token` Secret (same Application/namespace) as a DOWNLOAD-ONLY exception to the keyless C-A ruling, or is a new secret required; serving posture stays keyless either way.
Flip map: R-a/R-b/R-c CONFIRM a fit → C06 executes Shape A (new Strata Q4 profile(s) + one-line catalog adds); RECONFIRM blocked → C06 Shape B (verdict record only, no code — llama.cpp serving + C05's hygiene entries already answer the card). R-d decides C02's token mechanics only (existing Secret vs NEEDS_INFO→user).

## Out of scope
- Coder IQ1_M Strata rung (U3 declined). qwen3.6-35B-A3B Strata profile (U4 declined).
- Any Strata Q4 profile unless R-a/R-b confirm — C06 Shape A is the only sanctioned path; forcing it before the research verdict is out of scope.
- Re-serving 27B Q4/Q6, flash-next-q4, ornith rungs on llama.cpp (already served/enabled); C05 only routes them.
- New services/charts/ApplicationSets/secrets beyond the hf-token consumption question (R-d); container rebuilds only if C02's manual-pack step proves image-side.

## Commands
Repo validation, not unit tests (AGENTS.md "Pipeline specifics"). `export PATH=$HOME/.local/bin:$PATH` first (helm off PATH ⇒ pytest mass-skips).
- chart: `helm lint charts/llama-swap && helm template charts/llama-swap --debug >/dev/null`
- service render (TEST_SPEC §1 extract-and-render): `python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpuai-vals.yaml','w'))" && helm template llama-swap charts/llama-swap -f /tmp/gpuai-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai >/dev/null`
- suite (per-directory): `python3 -m pytest charts/llama-swap/tests -q` — new chunk tests pass AND pre-existing parity/schema/off-parity/untouched suites stay green; golden + `tests/evidence/strata-peers-expected.yaml` re-pins are test-author property (dev never edits).
- catalog: `python3 -c "import re,json; json.loads(re.sub(r'^\s*//.*$','',open('.opencode/opencode.jsonc').read(),flags=re.M))"` + presence greps of every new/hygiene id under gpu-ai `models`.
- trio grep per new Strata id (chart `strata.config.models` + service `peers.strata.models` + catalog): `grep -rn "<id>" charts/llama-swap/values.yaml services/gpu-ai/prod/values.yaml .opencode/opencode.jsonc` — all three surfaces.
- hf-token trio (U2 verification, C02 AC): `grep -rn "hf-token" charts/llama-swap/templates/secret-hf-token.yaml custom-values/gpu-ai/prod-values.yaml services/gpu-ai/prod/values.yaml` — ExternalSecret template + UUID + consumer wiring all present (verified TRUE at plan time: UUID 2ebdd082-…; the gated `qwen3.8-flash-next-orca-q6` serves with it today = the token has orcarouter access).
- container (only if C02's pack step lands image-side): `docker build => no-daemon, CI-deferred` (docker-build.yaml on the pushed branch authoritative).
- on-target (human-owned, NOT agent commands): setup catalog inventory capture on the claim, `strata serve --plan` verification of any new profile, models-PVC free-capacity check. Recorded as runbook follow-ups in RESULT.
- quality gate: `npx aislop ci --changes`.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | SC117 abliterated IQ3_XXS Strata rung (`qwen3.8-flash-next-strata-abliterated`) | M | 1 | [] | first new inner profile: establishes the profile/matrix/strip pattern C02/C06 extend |
| C02 | orcarouter gated Uncensored IQ3_XXS Strata rung (`qwen3.8-flash-next-strata-orca`, manual pack + HF_TOKEN) | M | 2 | [C01] | same template/matrix/service lines; consumes the R-d token answer |
| C03 | flash-next heretic-2 Q4_K_M llama.cpp rung (`qwen3.8-flash-next-heretic-q4`) | M | 3 | [C02] | file serialization only: shared families/matrix regions + gpu-ai golden re-pin chain |
| C04 | 27B heretic Q4_K_M-MTP llama.cpp rung (`qwen38-heretic`) | M | 4 | [C03] | same serialization rationale |
| C05 | Provider-catalog entries + context sizes + Q4-default routing | M | 5 | [C01,C02,C03,C04] | needs final landed ids; hygiene entries land regardless of research outcome (U5 second half) |
| C06 | **PENDING-AFTER-PLAN-RESEARCH** — Strata Q4 rungs (flash-next Q4 per U6, ornith-122B Q4 per U5), both shapes | M | 6 | [C01,C02,C05] + research verdicts R-a/R-b/R-c | pattern+gated-token precedent from C01/C02; catalog consumer |

## Wave order
Strictly linear: C01 → C02 → C03 → C04 → C05 → C06. C06 is additionally gated on the research round: it must not enter test/dev until its shape is fixed (test session writes C06 tests only after the flip). C03/C04 are functionally independent but share edit regions and the golden, hence chained.

## Risks / assumptions
- **The two user overrides sit on a sourced contradiction.** RESEARCH [S1][S11] rules 122B off-node and UD-Q4_K_XL past the arena; the user says they fit / belong on Strata. The plan honors BOTH: research re-derives from primary sources before a line of C06 Shape A is written; DECISIONS records the overrides as VERIFICATION-PENDING, not flipped verdicts. If research reconfirms blocked, the honest card answer is the llama.cpp serving + catalog routing (C05) — Shape B.
- **C-A keyless tension:** C02's gated download would consume the existing `hf-token` Secret in the Strata init container — a deliberate, DOWNLOAD-ONLY exception to the keyless ruling (which deleted serving-side keys). R-d rules; serving stays keyless unconditionally.
- New-profile run-config seeds are analogous, not on-target-generated (cf-77 crash precedent); on-target `--plan` verification and setup-inventory capture are human-owned runbook steps.
- Disk: +~90–150 GB of packs against the 500Gi models PVC (plus the existing set) — capacity is an on-target human gate before C02/C06 provisioning runs.
- Residency: every new Strata rung ttl 3600 + unloadTimeout 180; 96Gi cgroup and `--memory-limit-mib 92160` unchanged for IQ3_XXS-class arenas (~50 GiB ≤ today's IQ3_S). A Q4 rung (55–72 GiB experts) does NOT fit that envelope — C06 Shape A would need its own budget ruling (research-informed), flagging the documented −15% decode ROI regardless.
- Inner aliases stay unique inside the inner supervisor (no shadowing of `qwen3.8-flash-next`).
- Label-drift surface: this run's pipeline set comes from the card's `Pipeline:` board label — recorded on the card, not in files.
- Stale "180B-class" descBase comment: rides C03 if trivial, else chores card.
- All new catalog entries are 262144-class; no 1M variants.
