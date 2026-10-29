# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- RESEARCH.md is the feasibility authority for every chunk; its rulings 1–5 are load-bearing and not re-litigated by dev/review.
- Golden fixtures (`tests/golden/*.config.yaml`) and `tests/evidence/strata-peers-expected.yaml` are test-author property: dev never edits them; a needed re-pin routes coord→test session (cf-77/cf-83 precedent).
- New served ids are frozen by the plan (see chunk files); C05 consumes them verbatim.

## Decisions
- 2026-10-29 plan: Strata keeps IQ3_S as its flagship profile; NO Strata profile for flash-next Q4 (UD-Q4_K_XL 72 GiB experts exceeds the node's arena model — RESEARCH Q2/Q4). Rejected: a Strata q4 token — the repo's own values comment + Strata docs both rule it out.
- 2026-10-29 plan: Ornith-1.5-122B stays llama.cpp-only this ticket (upstream #3574 closed "add later", #4460 open); its deliverable in cf-86 is only provider-catalog routing (Open Q5 best guess = in scope). Rejected: forcing it onto Strata or forking upstream — out of scope. **STATUS 2026-10-29: superseded by U5 — the user rules served-from-Strata wanted; the llama.cpp-only stance is now the RESEARCH-side pending position re-verified by R-a/R-c (C06), and the catalog-routing deliverable stands (C05).**
- 2026-10-29 plan: new Strata rungs are Coder IQ1_M (C01, id `qwen3.8-flash-next-strata-coder`) and an abliterated IQ3_XXS-class rung (C02, id `qwen3.8-flash-next-strata-abliterated`), added as inner-matrix alternatives, never co-loaded; qwen3.6-35B-A3B/gyro coexist-tier profiles declined for now (Open Q4 best guess).
- 2026-10-29 plan: uncensored Strata ablation source = SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF (public, ships the exact installer-validated ISTA sizes + `strata/` folder). Rejected: orcarouter IQ3_XXS manual pack — gated, and an init-container HF_TOKEN passthrough re-adds the secret chain the keyless C-A ruling deliberately deleted.
- 2026-10-29 plan: llama.cpp ablation additions follow the measured ablation-quality ranking (heretic-style KLD ≈0.02–0.035 ≫ huihui-style 0.204): flash-next heretic-2 Q4_K_M (C03, id `qwen3.8-flash-next-heretic-q4`) and 27B heretic Q4_K_M-MTP (C04, id `qwen3.8-27b-heretic-q4`). Rejected: huihui-ai packs (perplexity +8–10%), a second orcarouter rung (already served as orca/ara).
- 2026-10-29 plan: "make Q4 the default" is implemented as routing-layer truth, not a Strata profile (Open Q6 best guess): the llama.cpp `qwen3.8-flash-next-q4` rung is already served; C05 verifies catalog presence and (only on the user's answer) re-routes the pipeline default — Strata itself stays IQ3_S. **STATUS 2026-10-29: U6 puts the Strata-fit half VERIFICATION-PENDING (R-b, C06); the default-route target becomes whichever Q4 rung the research validates (DECISIONS final-shape entry below).**
- 2026-10-29 plan: chunk waves strictly linear (C01→C05) to serialize golden/evidence re-pins and the shared families/matrix edit regions. Rejected: parallel waves 3 (C03‖C04) — functionally independent but they collide on the same chart lines and the same golden re-pin.

## Deferred
- Ornith-1.5-122B-on-Strata: revisit when upstream #4460 (or the announced community optimization) lands — new card, not a cf-86 edit. **SUPERSEDED 2026-10-29 by U5** — the user rules it in-scope-for-verification; now the R-a gate inside C06, not a deferral.
- orcarouter IQ3_XXS uncensored Strata pack: only if the user overrules the SC117 choice (would need init-container capability + gated HF_TOKEN decision + CI-deferred container build). **SUPERSEDED 2026-10-29 by U2** — user wants BOTH rungs; now C02, gated on R-d.
- qwen3.6-35B-A3B / gyro as coexist-tier Strata profiles: only on a Q4-answer flip. **CONFIRMED DECLINED 2026-10-29 by U4** — stays deferred.
- Fixing the stale "180B-class" descBase comment: rides C03 if trivial, otherwise a chores card.

## User rulings (2026-10-29 batched plan-question round, verbatim intent)
- 2026-10-29 human U1: breadth-with-swaps — multi-profile Strata catalog stands, 3–6 min restart swaps accepted. Rejected alternative: coexist-only tier (Coder/qwen36 ≤30 GiB). Why: user's words "Breadth with swaps".
- 2026-10-29 human U2: BOTH ablated Strata rungs — SC117 public GSQ-RCO-abliterated IQ3_XXS AND the orcarouter gated Uncensored pack; "HF_TOKEN should already be in the llama.cpp pod". Plan response: hf-token chain verified present ([repo] ExternalSecret + UUID 2ebdd082-… + main/tools consumers; the gated fnorca rung serves with it today); gated-download mechanics for the STRATA init is research item R-d, and consuming the existing Secret there is scoped as DOWNLOAD-ONLY against the keyless C-A ruling. Rejected: assuming the token reaches the Strata init today (it does not — the init container has no env by C-A).
- 2026-10-29 human U3: Coder IQ1_M profile DECLINED — draft C01 deleted.
- 2026-10-29 human U4: qwen3.6-35B-A3B on Strata DECLINED (no duplicate).
- 2026-10-29 human U5: OVERRIDE, recorded VERIFICATION-PENDING: "They should be served from Strata and we do need an entry in opencode.jsonc" (ornith ladder + flash-next-orca-q6). This contradicts RESEARCH [S1][S11] (arena math + upstream #3574 closed / #4460 open). Not folded silently into the plan and the llama.cpp routing is NOT kept against it either: R-a/R-c re-derive fit + what served-from-Strata requires today; C06 carries both shapes; the opencode.jsonc entries land regardless (C05).
- 2026-10-29 human U6: OVERRIDE, recorded VERIFICATION-PENDING: "It should fit. Double check." (flash-next Q4 on Strata). R-b re-derives which Q4 and against which measured caps (125 GiB node-spendable vs 96Gi cgroup vs --memory-limit-mib 92160 vs IQ3_S 46.84 GiB anchor); the original ruling stays standing until research says otherwise; C06 carries both shapes.
- 2026-10-29 human U7: slug `cf-86-feat-more-strata-models` kept.

## Renumap + final-shape decisions
- 2026-10-29 plan: renumber map draft→final — old C01(Coder) deleted; old C02→C01; NEW C02=orcarouter; old C03→C03; old C04→C04; old C05→C05; NEW C06=research-gated Strata Q4 rungs (status `pending-after-plan-research`). All draft chunks were pending, so renumbering is contract-clean.
- 2026-10-29 plan: After-Planning research round is a SCHEDULED RUN STAGE (card's legacy Research checklist has After Planning checked), scope R-a..R-d + the flip map in the plan file; runs after approval, before C06 test authoring; C01–C05 may proceed in parallel with it.
- 2026-10-29 plan: frozen ids updated — Strata: `qwen3.8-flash-next-strata-abliterated` (C01), `qwen3.8-flash-next-strata-orca` (C02), C06-shape-A ids `qwen3.8-flash-next-strata-q4` (+`ornith-1.5-122b-strata-q4` if R-a confirms); llama.cpp: `qwen3.8-flash-next-heretic-q4` (C03), `qwen38-heretic` (C04). C05 routes landed ids only; C06 shape A appends its own catalog line(s) when it lands (no phantom entries in C05).
- 2026-10-29 plan: "Q4 default" target = the Q4 rung the research verdict validates (Strata `-q4` if Shape A, else the already-served llama.cpp `qwen3.8-flash-next-q4`); the pipeline-default re-route in `.rulesync` skills stays a C05 conditional arm requiring explicit approval (cf-83 C01 pattern) — U6 spoke to fit, not to the routing surface.
