# PLAN: More models for Strata (card #86) — FINAL (post-answer round)
feature: 2026/2026-10-cf-86-feat-more-strata-models

## Goal
Widen the gpu-ai roster within the node's RAM law, per the answered batched round: two Strata ablation rungs (SC117 public GSQ-RCO-abliterated IQ3_XXS + orcarouter gated Uncensored IQ3_XXS manual pack) as time-shared inner-matrix alternatives, a Strata flash-next UD-Q4_K_XL rung (C06, the resolved outcome of the user's Q4 override — FINAL pins below), heretic-style coding ablations of flash-next and 27B on the llama.cpp side, and full provider-catalog routing in `.opencode/opencode.jsonc`. The user's two overrides were re-verified by the scheduled After-Planning research rounds: flash-next Q4 FITS (Shape-A-tweak, C06), ornith-122B stays blocked (Shape-B absence-record; llama.cpp serving + C05 hygiene entries unchanged) — DECISIONS "Research verdicts + final rulings" + RESEARCH.md Rounds 2+3 are the authority.

## Scope decisions from the batched round (U-rulings, full text in DECISIONS.md)
- U1 breadth-with-swaps: multi-profile Strata catalog stands, 3–6 min cold pins accepted.
- U2 BOTH ablated Strata rungs (SC117 + orcarouter); HF_TOKEN chain verified present on the llama.cpp side (AC-pinned in C02); gated-download mechanics for the Strata init are a research item (R-d).
- U3 Coder IQ1_M declined — the draft's Coder chunk is DELETED (see renumber map).
- U4 qwen3.6-35B-A3B on Strata declined (no duplicate).
- U5 OVERRIDE (VERIFICATION-PENDING at the time — RESOLVED by R-a/R-c, see research section): "served from Strata" + opencode.jsonc entries wanted → ornith half lands Shape-B (blocked upheld), the catalog half landed regardless (C05).
- U6 OVERRIDE (VERIFICATION-PENDING at the time — RESOLVED by R-b/U8: FITS, C06 FINAL Shape-A-tweak): flash-next Q4 "should fit. Double check." → it does, with the conv-trim + session round-trip envelope.
- U7 slug `cf-86-feat-more-strata-models` kept.

**Renumber map (draft → final):** old C01 (Coder) deleted; old C02→C01 (SC117); NEW C02 (orcarouter); old C03→C03; old C04→C04; old C05→C05; NEW C06 (research-gated). All pre-existing chunks were `pending`, so renumbering is contract-clean; nobody should chase draft ids after this commit.

## Scheduled stage: After-Planning research round — **RESOLVED 2026-10-29** (kept for the record)
Rounds 2+3 landed in RESEARCH.md; verdicts + the U8 ruling are recorded in DECISIONS.md "Research verdicts + final rulings". Outcome per item: **R-b** OVERTURNED round-1 — flash-next UD-Q4_K_XL FITS as a single-profile time-share (U6 confirmed), and U8's session round-trip tweak verified native in Strata 0.2.7 → C06 Shape-A-tweak FINAL. **R-a** UPHOLDS the ornith block (v0.2.7 kernel constants, #3574 "add later", #4460 open — not RAM/arch/files) → `ornith-1.5-122b-strata-q4` = SHAPE-B absence-arm; C05's hygiene entries + llama.cpp serving unchanged. **R-c** disk gate: user ruled "Enough free — proceed" (+260–290 GB; ~+5 GB/session-file noted). **R-d**: existing hf-token Secret sanctioned for C02's download-only init (setup.py@0.2.7 has zero auth support — manual fetch). The pre-registered fallback (on-target HIP session round-trip fails → UD-IQ4_XS envelope, conv 32 / cgroup 108Gi / memory-limit 102400) is a human-owned on-target gate, pins kept in C06.md. Original scope items retained below.
- **R-a Ornith-1.5-122B Q4 on Strata:** re-derive the arena math from primary sources; explicitly test whether the existing ruling conflated (i) page-locked arena fit, (ii) llama.cpp/llama-swap LOADER support, (iii) node RAM ceiling; which 122B Q4 GGUFs exist in Strata-validated packings; current state of upstream #3574/#4460 and the announced community optimization.
- **R-b flash-next Q4 on Strata:** which Q4 (unsloth UD-IQ4_XS 55 GiB experts vs UD-Q4_K_XL 72 GiB vs orcarouter IQ4_XS ~97.5 GB files); pin down what the "125 GiB" figure actually caps (node spendable RAM vs cgroup 96Gi vs `--memory-limit-mib 92160`) against the measured IQ3_S 46.84 GiB anchor; whether a Q4 profile fits with trimmed conversation-cache/KV and at what decode-ROI (documented −15% decode on R9700 at UD-Q4_K_XL).
- **R-c what "served from Strata" concretely requires today:** setup.sh catalog inventory for unsloth/ornith/orcarouter paths, upstream issue status at run date, GGUF file existence for Q4 rungs, manual-pack (ORCA.md-class) feasibility at Q4 sizes, models-PVC capacity math (500Gi claim vs +43–111 GB packs).
- **R-d gated-pack download for the Strata init:** does setup/manual path honor `HF_TOKEN` (huggingface_hub); may the init container consume the EXISTING `hf-token` Secret (same Application/namespace) as a DOWNLOAD-ONLY exception to the keyless C-A ruling, or is a new secret required; serving posture stays keyless either way.
Flip map (as scheduled — now RESOLVED, see the verdict block above): R-a/R-b/R-c CONFIRM a fit → C06 Shape A (new Strata Q4 profile(s) + one-line catalog adds) — CONFIRMED for flash-next UD-Q4_K_XL with the U8 tweak, and R-d's answer unblocked C02's token mechanics; RECONFIRM blocked → Shape B — landed for ornith only (absence-arm + record).

## Out of scope
- Coder IQ1_M Strata rung (U3 declined). qwen3.6-35B-A3B Strata profile (U4 declined).
- An `ornith-1.5-122b-strata-q4` profile (R-a upheld the block — Shape-B absence-arm only; re-watch #4460). A flash-next Strata Q4 profile OUTSIDE C06's FINAL pins (any deviation re-opens the gate).
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
- C06 pins (chart+render level): `grep -n -- "--conversation-cache-mib 8192\|--conversation-cache-slots 16\|--slot-save-path /models/strata/sessions\|--memory-limit-mib 95232" charts/llama-swap/values.yaml` all hit in the `engineProfileStrataQ4` arm; negative grep — `grep -n -- "--batch\|--layer-split\|--prompt-cache 0\|--ple-io ram" charts/llama-swap/values.yaml` finds NONE in the Q4 arm (the existing documented-toggle comments elsewhere may match `--ple-io ram` as a toggle note — scope the check to the Q4 block, e.g. via the rendered `strata-q4.json` from the gpu-ai render, which must be clean); `grep -n "limits:" -A1` shows strata container 100Gi; `grep -rn "ornith-1.5-122b-strata" charts services .opencode` returns NOTHING (Shape-B absence-arm, suite-pinned too); golden + peers-evidence re-pin to the five-id list stays test-session property.
- container (only if C02's pack step or C06's checkout-version gate lands image-side): `docker build => no-daemon, CI-deferred` (docker-build.yaml on the pushed branch authoritative).
- on-target (human-owned, NEVER agent commands): setup catalog inventory capture on the claim, `strata serve --plan` verification of any new profile (incl. C06's PLE-mmap pin), models-PVC free-capacity spot check, and C06's first **HIP session save/restore round-trip** — its failure triggers the pre-registered UD-IQ4_XS fallback per DECISIONS, never a dev-side decision. Recorded as runbook follow-ups in RESULT.
- quality gate: `npx aislop ci --changes`.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | SC117 abliterated IQ3_XXS Strata rung (`qwen3.8-flash-next-strata-abliterated`) | M | 1 | [] | first new inner profile: establishes the profile/matrix/strip pattern C02/C06 extend |
| C02 | orcarouter gated Uncensored IQ3_XXS Strata rung (`qwen3.8-flash-next-strata-orca`, manual pack + HF_TOKEN) | M | 2 | [C01] | same template/matrix/service lines; consumes the R-d token answer |
| C03 | flash-next heretic-2 Q4_K_M llama.cpp rung (`qwen3.8-flash-next-heretic-q4`) | M | 3 | [C02] | file serialization only: shared families/matrix regions + gpu-ai golden re-pin chain |
| C04 | 27B heretic Q4_K_M-MTP llama.cpp rung (`qwen38-heretic`) | M | 4 | [C03] | same serialization rationale |
| C05 | Provider-catalog entries + context sizes + Q4-default routing | M | 5 | [C01,C02,C03,C04] | needs final landed ids; hygiene entries land regardless of research outcome (U5 second half) |
| C06 | Strata Q4 rung — **FINAL Shape-A-tweak**: `qwen3.8-flash-next-strata-q4` = UD-Q4_K_XL + conv-cache 8192 (slots 16) + `--slot-save-path /models/strata/sessions` + cgroup 100Gi / `--memory-limit-mib 95232` + negative-pins + PLE-mmap pin at the on-target gate; ornith-122B-Q4 = SHAPE-B absence-record | M | 6 | [C01,C02,C05] | pattern+gated-token precedent from C01/C02; catalog consumer |

## Wave order
Strictly linear: C01 → C02 → C03 → C04 → C05 → C06. C06's research gate is RESOLVED (2026-10-29, DECISIONS "Research verdicts + final rulings" + RESEARCH.md Rounds 2+3) — C06 is testable now like the rest. C03/C04 are functionally independent but share edit regions and the golden, hence chained.

## Risks / assumptions
- **The two user overrides are RESOLVED by the After-Planning rounds** (was: a sourced contradiction): R-b overturned the flash-next-Q4 block (UD-Q4_K_XL fits as a single-profile time-share; U6 confirmed, U8 ruled the conv-trim + session round-trip tweak), R-a upheld the ornith block (Shape-B absence-record). DECISIONS "Research verdicts + final rulings" is the authority; C06's FINAL pins + pre-registered fallback carry the operational shape.
- **Decode ROI survives the fit overturn:** UD-Q4_K_XL is the documented ~−15% decode class vs IQ3_S on the R9700 — U8 chose it knowingly; the commit message must say so.
- **C-A keyless tension RESOLVED by R-d:** C02's gated download consumes the existing `hf-token` Secret in the Strata init as a DOWNLOAD-ONLY exception (setup.py@0.2.7 has zero auth support → manual fetch); serving stays keyless unconditionally.
- New-profile run-config seeds are analogous, not on-target-generated (cf-77 crash precedent); on-target `--plan` verification and setup-inventory capture are human-owned runbook steps.
- Disk: +~90–150 GB of packs against the 500Gi models PVC (plus the existing set) — capacity is an on-target human gate before C02/C06 provisioning runs.
- Residency: every new Strata rung ttl 3600 + unloadTimeout 180; 96Gi cgroup and `--memory-limit-mib 92160` unchanged for the IQ3_S/IQ3_XXS-class rungs (~50 GiB arenas). The Q4 rung rides its OWN ruled envelope — cgroup 100Gi + `--memory-limit-mib 95232` (U8 + Round-3; DECISIONS authority), fallback to the UD-IQ4_XS 108Gi/102400 shape pre-registered for a failed on-target HIP session round-trip (human gate).
- Inner aliases stay unique inside the inner supervisor (no shadowing of `qwen3.8-flash-next`).
- Label-drift surface: this run's pipeline set comes from the card's `Pipeline:` board label — recorded on the card, not in files.
- Stale "180B-class" descBase comment: rides C03 if trivial, else chores card.
- All new catalog entries are 262144-class; no 1M variants.
