# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- RESEARCH.md is the feasibility authority for every chunk; its rulings 1–5 are load-bearing and not re-litigated by dev/review.
- Golden fixtures (`tests/golden/*.config.yaml`) and `tests/evidence/strata-peers-expected.yaml` are test-author property: dev never edits them; a needed re-pin routes coord→test session (cf-77/cf-83 precedent).
- New served ids are frozen by the plan (see chunk files); C05 consumes them verbatim.

## Decisions
- 2026-10-29 plan: Strata keeps IQ3_S as its flagship profile; NO Strata profile for flash-next Q4 (UD-Q4_K_XL 72 GiB experts exceeds the node's arena model — RESEARCH Q2/Q4). Rejected: a Strata q4 token — the repo's own values comment + Strata docs both rule it out.
- 2026-10-29 plan: Ornith-1.5-122B stays llama.cpp-only this ticket (upstream #3574 closed "add later", #4460 open); its deliverable in cf-86 is only provider-catalog routing (Open Q5 best guess = in scope). Rejected: forcing it onto Strata or forking upstream — out of scope.
- 2026-10-29 plan: new Strata rungs are Coder IQ1_M (C01, id `qwen3.8-flash-next-strata-coder`) and an abliterated IQ3_XXS-class rung (C02, id `qwen3.8-flash-next-strata-abliterated`), added as inner-matrix alternatives, never co-loaded; qwen3.6-35B-A3B/gyro coexist-tier profiles declined for now (Open Q4 best guess).
- 2026-10-29 plan: uncensored Strata ablation source = SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF (public, ships the exact installer-validated ISTA sizes + `strata/` folder). Rejected: orcarouter IQ3_XXS manual pack — gated, and an init-container HF_TOKEN passthrough re-adds the secret chain the keyless C-A ruling deliberately deleted.
- 2026-10-29 plan: llama.cpp ablation additions follow the measured ablation-quality ranking (heretic-style KLD ≈0.02–0.035 ≫ huihui-style 0.204): flash-next heretic-2 Q4_K_M (C03, id `qwen3.8-flash-next-heretic-q4`) and 27B heretic Q4_K_M-MTP (C04, id `qwen3.8-27b-heretic-q4`). Rejected: huihui-ai packs (perplexity +8–10%), a second orcarouter rung (already served as orca/ara).
- 2026-10-29 plan: "make Q4 the default" is implemented as routing-layer truth, not a Strata profile (Open Q6 best guess): the llama.cpp `qwen3.8-flash-next-q4` rung is already served; C05 verifies catalog presence and (only on the user's answer) re-routes the pipeline default — Strata itself stays IQ3_S.
- 2026-10-29 plan: chunk waves strictly linear (C01→C05) to serialize golden/evidence re-pins and the shared families/matrix edit regions. Rejected: parallel waves 3 (C03‖C04) — functionally independent but they collide on the same chart lines and the same golden re-pin.

## Deferred
- Ornith-1.5-122B-on-Strata: revisit when upstream #4460 (or the announced community optimization) lands — new card, not a cf-86 edit.
- orcarouter IQ3_XXS uncensored Strata pack: only if the user overrules the SC117 choice (would need init-container capability + gated HF_TOKEN decision + CI-deferred container build).
- qwen3.6-35B-A3B / gyro as coexist-tier Strata profiles: only on a Q4-answer flip.
- Fixing the stale "180B-class" descBase comment: rides C03 if trivial, otherwise a chores card.
