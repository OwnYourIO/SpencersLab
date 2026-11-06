# Independent re-review — cf-86 (card #86) against the ORIGINAL OWNER ASK

Reviewer: fresh session, no prior review history. Date 2026-10-31. Range reviewed:
`cf-86-feat-more-strata-models` @ `aa39a18cf` (30 commits from base `617e18488`; base verified an
ancestor — `git merge-base --is-ancestor 617e18488 HEAD` ⇒ true).
READ-ONLY run: no git write ops, no commits, no pushes; scratch under
`/tmp/opencode/re-review-cf86/`; writes only in this folder.

Method: ask-to-artifact map. Every claim below is from a command run in this session or a file
read in this session — never from plan prose. Upstream claims re-verified TODAY (upstream moves).

## 0. Live-render authority used for every "is it actually served" claim

```
export PATH=$HOME/.local/bin:$PATH
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; \
  yaml.safe_dump(d, open('/tmp/opencode/re-review-cf86/gpuai-vals.yaml','w'))"
helm template llama-swap charts/llama-swap -f /tmp/opencode/re-review-cf86/gpuai-vals.yaml \
  --set domain=spencerslab.com --set clusterName=gpu-ai        # rc 0, 2680 lines
```

Rendered ConfigMaps: `llama-swap-config` (60 models), `strata-config` (4 models),
`strata-profile` (`strata-iq3_s.json`, `strata-strix-iq3_s.json`, `strata-orca-iq4_xs.json`,
`strata-q4.json`). Base render (same command against a `git archive 617e18488` export) holds 58 +
2 models, so the range's serving delta is exactly:

- llama.cpp side ADDED: `qwen3.8-flash-next-heretic-q4`, `qwen38-heretic`; REMOVED: none.
- Strata side ADDED: `qwen3.8-flash-next-strata-orca`, `qwen3.8-flash-next-strata-q4`; REMOVED:
  none (SC117 `…-strata-abliterated` net-absent — C01 added, C08 swept;
  `grep -rc "qwen3.8-flash-next-strata-abliterated" charts services .opencode` ⇒ 0/0/0).
- Outer routing: `peers.strata.models` = the four inner arenas (render-verified ⇒ routable, not
  just declared).

## 1. Ask-to-artifact map

| # | Card words (verbatim ask) | What the shipped repo actually provides (verified this session) | Disposition given, and is it TRUE today | Verdict |
|---|---|---|---|---|
| 1 | "understand if strata can handle live swapping… if a single strata server can serve more than one model or if I'll need multiple" | One Strata pod, four time-shared arenas (`strata-config.matrix.sets.main = "(p \| s \| o \| q)"`, alternatives only); inner `ttl: 3600` (strix 1800), outer `peers.strata.timeouts.responseHeader: 1800`, inner `healthCheckTimeout: 1800`; no inner preload | RESEARCH Q1: no in-process swap, `#1738` closed `not_planned`. **Verified today via GitHub API: #1738 state=closed, state_reason=not_planned, closed_by Niko1221 (OWNER) 2026-10-13.** Answer + shipped shape agree | **DELIVERED** |
| 2 | "Qwen 3.8 Flash-Next Q4 (**Lets make Q4 the default**)" | Model half: TWO Q4 rungs — new Strata `qwen3.8-flash-next-strata-q4` (`strata-q4.json`: `--pack …/packs/unsloth-ud-q4_k_xl`, `--native …UD-Q4_K_XL-00001-of-00004.gguf`, `--memory-limit-mib 95232`, `--conversation-cache-mib 8192`, slots 16, `--slot-save-path /models/strata/sessions`, pod `limits.memory: 100Gi`) + pre-existing llama.cpp `qwen3.8-flash-next-q4`. Trio verified by grep: chart 2 / service 1 / catalog 2 hits. **Default half: NOTHING.** `.rulesync/skills/pipeline-models/SKILL.md:31,49`, `pipeline-kickoff/SKILL.md:26`, `boards/SKILL.md:121` still route Flash+Local to `gpu-ai/qwen3.8-flash-next-strata` (IQ3_S); zero `.rulesync/**` diffs in the range; matrix order `(p \| s \| o \| q)` still favours `p`=IQ3_S; no serving-layer default exists at all | Plan made it a conditional arm needing explicit approval ("U6 spoke to fit, not to the routing surface"), never asked, and routed it to the run-end user bucket (STATE `run_state.final_round.routed_run_end`: "pipeline-default Q4 re-route (conditional arm)"). No owner ruling ever declined it | **MISSED** (sub-clause; the model itself is DELIVERED) |
| 3 | "Qwen 3.8 27B Q4 and Q6" | `qwen3.8-27b-q4` (UD-Q4_K_XL, MTP) and `qwen3.8-27b-q6` (UD-Q6_K_XL, MTP) both live in the gpu-ai render, both in `sets.main`, both already in the catalog at 262144 at base — i.e. served+routable before and after; the ticket adds a law (`test_c05_card_asks_already_served_and_routable`) not a rung | "Already served/enabled; C05 only routes them" — **TRUE** (base render + base catalog both contain them). Strata reading also closed honestly: fetched `Niko1221/Strata@v0.2.8 setup.py` (639,798 B) + `docs/MODELS.md` today — **no 27B dense model anywhere in `FAMILIES`/MODELS.md** (catalog = qwen/swift/coder/unsloth/gyro/nvfp4/qwen36/deepseek41), so 27B-on-Strata is not a supported path | **DELIVERED-AS-RE-ROUTED-BY-FACT** |
| 4 | "A couple ablated models of qwen 3.8 flash q4. I know I want orca, but want to know what else people use and like for coding. Please research this." | Three ablated flash-next surfaces: Strata `qwen3.8-flash-next-strata-orca` (IQ4_XS, `strata-orca-iq4_xs.json`: 3-shard `…Uncensored-IQ4_XS-0000[123]-of-00003.gguf`, `--ple-gguf`→shard 1, conv 8192, cap 92160); llama.cpp `qwen3.8-flash-next-orca-q6` (pre-existing, **made agent-routable by this ticket** — absent from the base catalog); NEW `qwen3.8-flash-next-heretic-q4`. Byte pins live-checked today: HF tree `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` IQ4_XS = 44,766,155,936 + 44,735,995,008 + 7,971,004,256 = **97,473,155,200** — exactly `containers/strata/files/byte_pins.env` | Research delivered (RESEARCH Q3: heretic KLD 0.019–0.035 ≫ huihui 0.204; ranking heretic > orca ≈ AtomicChat > huihui). SC117's rung was added (C01) then removed by owner ruling U9.3 — and its stated basis is TRUE: HF tree today shows SC117 abliterated publishes **only IQ2_XS/IQ3_S/IQ3_XXS/Q2_0, no Q4 tier at all** | **DELIVERED** |
| 5 | "A couple ablated models of qwen 3.8 27B q4… I know I want orca, not sure what else is out there and makes sense in strata" | NEW llama.cpp `qwen38-heretic` (Q4_K_M-mtp, joined `sets.main` as `q38her`); 27B ablations already served and routable: `qwen38-orca` (Q6_K), `qwen38-orca-f16`, `qwen38-ara`, `qwen38-rana`, `qwen38-humanlike`. Strata for 27B: not a path (row 3's upstream check) | Research delivered (RESEARCH Q3 27B field: orcarouter/huihui/0bserverx/HauhauCS/nerkyor/mradermacher/ayozhee). Gap note: the rejection "a second orcarouter rung (already served as orca/ara)" is true for the family but **not for the asked Q4 class** — orcarouter 27B Q4_K_M 16,810,714,496 B / Q4_K_S 15,825,298,816 / IQ4_XS 15,309,039,200 exist upstream (HF tree read today), and served orca is Q6_K/F16 only | **DELIVERED** (with minor-1 below) |
| 6 | "ornith-1.5-122b q4" | llama.cpp serves `ornith-1.5-122b-q3/q4/q5/q6` (UD-Q4_K_XL among them; in `sets.solo`), and this ticket made them agent-routable — base catalog had **zero** ornith entries. No `ornith-1.5-122b-strata*` anywhere: `grep -rn "ornith-1.5-122b-strata" charts services containers .opencode custom-values` ⇒ 0 hits (suite-pinned absence arm) | Shape-B "blocked upstream" — **re-verified today**: #3574 state=closed, state_reason=not_planned (closed by the format bot 2026-10-26; the OWNER comment 2026-10-22 "Ornith 122B is not in the plan for the next release, but we want to add it later" is real, quoted verbatim); #4460 still open (`needs-format`, 1 comment); releases v0.2.8 (2026-10-29) and v0.2.9 (2026-10-31) mention **no** Ornith and no q36 prerequisite issue. Owner's U5 override ("served from Strata") was honoured as far as upstream allows: catalog half landed, Strata half recorded with the fork cost quantified | **DELIVERED-AS-RE-ROUTED-BY-OWNER** + the Strata half **DEFERRED-WITH-AUTHORITY** |
| 7 | "We'll need to update the .opencode/opencode.jsonc with these and context size as well" | gpu-ai catalog 86→82 keys: **+9** (`qwen3.8-flash-next-heretic-q4`, `qwen38-heretic`, `qwen3.8-flash-next-strata-orca`, `qwen3.8-flash-next-strata-q4`, `qwen3.8-flash-next-orca-q6`, `ornith-1.5-122b-q3/q4/q5/q6`), all `modelID==key`, `tools: true`, `limit.context: 262144`; **−13** phantom entries. `providers.gpu-ai.settings` and `default_agent` byte-unchanged (suite-pinned) | The −13 is unrequested by the card but verified correct: none of the 13 is served by the gpu-ai render at base **or** head (checked in both renders), the provider's `baseURL` is `llama.spencerslab.com/v1` (this chart's endpoint), and the same ids still exist in the machine-local `gpu-moe` catalog (`llama-moe.spencerslab.com`) — so no capability was lost, only wrong-provider entries removed. `tests/pipeline-models/surface.sh` M3 catalog HOLD stays green ⇒ no route points at a deleted id | **DELIVERED** |

## 2. Findings (severity order)

**major-1 (ask-level gap, not a code defect) — the owner's "Lets make Q4 the default" never landed,
at any layer.** Evidence: `grep -rn "qwen3.8-flash-next" .rulesync/` → `pipeline-models/SKILL.md:31`
combination rule and `:49` favorites row both still name `gpu-ai/qwen3.8-flash-next-strata`
("(Strata default; …)"); `pipeline-kickoff/SKILL.md:26` and `boards/SKILL.md:121` likewise; zero
`.rulesync/**` and zero `.opencode/skills/**` diffs across all 30 commits. Catalog presence is not
defaulting: the Q4 ids are selectable, nothing routes to them by default. Strata matrix order
`(p | s | o | q)` also keeps IQ3_S first. Worse, `test_catalog_contract.py::
test_c05_default_route_flip_not_applied_without_a_repin` asserts the *un-flipped* route, so the
gap is hardened: closing it takes the coordinated rulesync + surface.sh re-pin the law names.
Why it matters: it is the only element of the card written as an instruction that has no shipped
consequence, and the hold-authority is the plan's own reading ("U6 spoke to fit, not routing"), not
an owner ruling. It IS recorded as a user call (STATE `routed_run_end`, `revision_final_round.carry`
"user bucket: … Q4-default"), so it is not hidden — but no run stage ever asked the owner the
question. **Owner decision needed; ~3-file `.rulesync/skills/{pipeline-models,pipeline-kickoff,
boards}` edit + test-session re-pin of `tests/pipeline-models/surface.sh` +
`test_catalog_contract.py`.**

**minor-1 — 27B orca was never offered at the asked quant.** Card: "ablated models of qwen 3.8 27B
**q4**… I know I want orca". Shipped 27B orca rungs are Q6_K and F16 (`qwen38-orca`,
`qwen38-orca-f16`); the new Q4-class ablation is `qwen38-heretic` only. Upstream (HF tree, today)
`orcarouter/Qwen3.8-27B-Uncensored-GGUF` publishes Q4_K_M 16.8 GB / Q4_K_S 15.8 / IQ4_XS 15.3, and
RESEARCH [S22] already noted a public ungated mirror (`bartowski/orcarouter_…`). The DECISIONS
rejection ("already served as orca/ara") is true for the family, false for the Q4 class, and no
owner ruling covers it. Breadth is still satisfied (1 new + 4 pre-existing 27B ablations, all
routable), so minor. Fix if elected: one family rung + catalog entry, ~the C04 shape.

**minor-2 — posture record divergence (record hygiene, tree is fine).** Claimed in
STATE `revision_final_round_2026_10_31.posture_agent_shell`: plain 0F/373P/11S, armed 0F/381P/3S.
Measured here: **plain 0F/376P/8S, armed 0F/384P/0S** — which reproduces TEST_SPEC §9.18 exactly.
Reconciled, not argued: the 3-arm delta is torch-gated `convert_lora` arms (torch present in this
env), and this run's 8 plain skips are exactly 7× `RUN_HF_CHECK` + 1× `RUN_FLAG_AUDIT` (read with
`-rs`). STATE's own `ledger_correction` already attributes it to env skip-gating and routed the
ledger fix to the test session. No hidden red.

**nit-1 — RESEARCH [S7] carries a stale byte total.** RESEARCH cites unsloth
`UD-Q4_K_XL` = 111,334,652,184 B; HF tree read today = **111,334,654,784 B** (4 shards). The
shipped surfaces are right (values.yaml:2031, host-prep note:210/306, `test_strata_runbook.py:252`
with `SUPERSEDED_SLIPS = ("111,334,256,784",)`); only the RESEARCH prose lags by 2,600 B.

**nit-2 — upstream moved right after landing (no action).** Strata **v0.2.9** published
2026-10-31T08:02Z — after the last commit (`aa39a18cf` 07:49Z; C07 landed 04:22Z), so the 0.2.8 /
0.1.54 pin was current at landing. v0.2.9 (engine 0.1.55) adds gfx12/R9700 prompt-kernel wins
(+3.5–6.1%) the strix/R9700 rungs would enjoy; Renovate owns the bump.

## 3. Validation posture (this session, `PATH=$HOME/.local/bin:$PATH`, deps: system pytest/pyyaml/websockets/jsonschema)

| Run | Result | Claim compared | Match |
|---|---|---|---|
| `helm lint charts/llama-swap` | 1 chart linted, **0 failed** (1 INFO: icon) | — | ✓ |
| `helm template charts/llama-swap --debug` | rc 0, 1794 lines | — | ✓ |
| gpu-ai service render (plan Commands) | rc 0, 2680 lines, no `OVERRIDE_*` sentinels observed | — | ✓ |
| `pytest charts/llama-swap/tests -q` (plain) | **0F / 376P / 8S** | TEST_SPEC §9.18 "0F/376P/8S" | **exact** |
| `RUN_HF_CHECK=1 RUN_FLAG_AUDIT=1 pytest …` (armed) | **0F / 384P / 0S** | TEST_SPEC §9.18 "0F/384P/0S" | **exact** |
| same, vs STATE record 0F/373P/11S / 0F/381P/3S | −3P/+3S | env-gated (torch) | explained — minor-2 |
| `pytest containers/strata/tests -q` | **24 passed** | "containers 24P" | **exact** |
| `bash tests/agent-board-coord/rulesync-surface.sh` | rc 0, 19 ok, 0 FAIL | 19 | ✓ |
| `bash tests/agent-board-coord/gate.sh` | rc 0, 22 ok, 0 FAIL | 22 | ✓ |
| `bash tests/agent-board-coord/agents-md.sh` | rc 0, 9 ok, 0 FAIL | 9 | ✓ |
| `bash tests/pipeline-models/surface.sh` | rc 0, 6 ok (M1–M6 incl. `rulesync generate --check` clean) | 6 | ✓ |
| `bash tests/pipeline-gates/validation-fix.sh` | rc 0, 8 ok | 8 | ✓ |
| `npx aislop ci --changes` | **0 errors / 0 warnings / 0 fixable, 62 files** | "aislop 100, 0/0/0" | ✓ |
| validation-weakening scan (`git diff 617e18488..HEAD` on both test trees) | no removed skip/xfail; added skipifs are only the established `helm`-present and `RUN_HF_CHECK`/`RUN_FLAG_AUDIT` env gates | — | ✓ nothing weakened |

Armed run also re-verifies live, today, against the network: the C03/C04 HF packs, the C08
orcarouter IQ4_XS tree (+ its 401 gate) and the C06 unsloth UD-Q4_K_XL tree.

## 4. Upstream spot-checks re-run today (the "research says blocked" verdicts)

- `#1738` hot-switch API — closed / `not_planned`, by the OWNER ⇒ live-swap answer holds.
- `#3574` ornith-122B — closed / `not_planned`; owner comment "not in the plan for the next
  release, but we want to add it later" verified verbatim (housekeeping bot did the mechanical
  close; the research text attributes the close to the maintainer — immaterial).
- `#4460` ornith request — still open, 1 comment ⇒ nothing new.
- Releases v0.2.8 / v0.2.9 — zero Ornith mentions, zero q36-prerequisite mentions ⇒ block holds.
- v0.2.8 body confirms C07's re-pin basis: "The app is 0.2.8. Control and every engine package are
  0.1.54", "The conversation cache no longer runs short when the PLE table is locked (#4518)" and
  the R9700 decode win (73.7→79.7 story, 106.3→107.8 code ⇒ ~+8%/+1.4%, plan said +5–8%).
- `#4518` closed `completed` 2026-10-29T22:48Z; GHCR tags `0.2.8-rocm-gfx120x` and
  `0.2.8-rocm-gfx1151` both exist ⇒ `containers/strata/Dockerfile` pins are live and pullable.
- Session-automation issues `#3341/#3565/#3891/#4306` all **open** today ⇒ the values.yaml Q4-arm
  comment "nothing calls save/restore automatically … still open at 0.2.8" is accurate as of today.

## 5. Deferred (out of the verdict, already routed by the run — confirmed present in the record)

On-target human gates: `strata serve --plan` per new profile; HIP session save/restore round-trip
(pre-registered UD-IQ4_XS 32768/108Gi/102400 fallback if it fails); `iq_pack --compat-bf16`
fidelity + PLE shard placement at the first IQ4_XS provisioning; `df` headroom; claim cleanup with
`.pack-orca` **first** (tier-independent marker — the documented trap). User bucket: strix catalog
entry, 10 pre-existing unroutable rungs, machine-local twin catalogs, **pipeline-default Q4
re-route**, remote-branch disposition. Chores: descBase 180B-vs-125B + KLD phrasing, cf-78 stale
reference, PROVENANCE line-count, PIN-ME 1209-vs-1160, NVMe/heartbeat/dev-boards/list_comments
friction, agents-sync convention promotions. Git hygiene: STATE records that the first final-review
launch committed **and pushed** `5a03cec40` out of contract — content verified sound, disposition
of the pushed branch is owner-only; this re-review performed no git writes and confirms the tree is
clean (`git status --short` empty).

## 6. Verdict

**APPROVED-WITH-GAPS.**

The artifact set is real, render-verified, and every "already served"/"blocked upstream"
disposition I attacked held against primary sources today. Six of the seven ask elements landed
(2 new Strata arenas + 2 new llama.cpp rungs + 9 catalog entries at 262144 + the live-swap answer),
and every owner ruling (U1–U9) is visible in the shipped state. The single gap is the owner's own
parenthetical — **"Lets make Q4 the default"** — which landed as catalog presence only, with the
default route still IQ3_S on all three routing surfaces and pinned by a test.

Gap list, routed:
1. **major-1 → owner (one decision):** elect the Q4 default target (`gpu-ai/qwen3.8-flash-next-strata-q4`
   or `gpu-ai/qwen3.8-flash-next-q4`), then a rulesync trio edit + `tests/pipeline-models/surface.sh`
   and `test_catalog_contract.py::test_c05_default_route_flip_not_applied_without_a_repin` re-pin
   (test-session property). Until then the card's instruction is unexecuted.
2. **minor-1 → owner election, then a one-rung chunk** if they want 27B orca at Q4-class
   (orcarouter Q4_K_M, ungated mirror, ~17 GB).
3. **minor-2 → test session:** reconcile the §9.17/§9.18 vs `posture_agent_shell` counts into one
   per-environment ledger line (already flagged in STATE `ledger_correction`).
4. **nit-1/nit-2 → chores:** RESEARCH [S7] byte total; v0.2.9 is now current (Renovate bump).

## 7. Post-record addendum (same session, after §6 was written)

- **Board state today (dev-boards, read-only):** card #86 (`Yb9sccTQ3wq2445ib`) sits in **Executing**,
  not Review — while the run's hand-off comment asserts "Card stays in Review for your
  Finished/Rework call." Either the Review hand-off never persisted (board was down at exit) or the
  owner pulled the card back after the "second read-only review APPROVED" round. Either reading
  says the same thing for the verdict: the card is **not** in an owner-accepted state, consistent
  with the open major-1 (Q4-default) decision. Owner-owned move; no action by this review.
- **Row 7 rationale refined (still DELIVERED):** live `llama-moe.spencerslab.com/v1/models` today
  returns 89 ids and contains **none** of the 13 removed ids either — the removal cost no *live*
  capability anywhere; what the machine-local gpu-moe catalog preserves for 9 of them are stale
  catalog entries (user-owned surface: those 9 gpu-moe entries are themselves dead-against-live
  and belong in the same user-bucket cleanup). The repo-side removal stands correct on both
  readings (repo catalog must not list ids the repo does not serve — the ids have been absent from
  both renders since the 2026-10-22 CR3 sweep, per the golden fixtures + `REMOVED_IDS` law).
- **Re-run confirmation (later commands of this session):** combined suite
  `pytest charts/llama-swap/tests containers/strata/tests` = **400 passed / 8 skipped** plain and
  **408 passed / 0 skipped** armed (== §3's 376+24 / 384+24 exactly); `npx aislop ci --changes` =
  **0/0/0, 62 files**; catalog diff base↔head = exactly **+9/−13**, every kept id resolves to a
  served model, alias, or matrix profile (`:caption`/`:tags` are served matrix profiles;
  `ctx-1m` macro `-c 1010000` ⇒ catalog 1010000 is the served ctx). No-phantom result: **zero**
  repo-catalog ids without a served backend.
- **minor-1 reconfirmed against the served repo name:** `qwen38-orca` serves
  `orcarouter/Qwen3.8-27B-Uncensored-GGUF:Q6_K`, and that exact repo's live tree carries
  Q4_K_M 16,810,714,496 B / Q4_K_S 15,825,298,816 / IQ4_XS 15,309,039,200 — the asked Q4-class
  orca-27B was one annotation away. `qwen38-heretic` ships Q4_K_M-mtp, so the 27B-Q4-ablation class
  is served — by heretic, not orca.
- **§4 upstream spot-checks re-ran clean again today** (same commands, same results); no drift since
  §4 was recorded. Tree still clean; no git writes performed by this review.
