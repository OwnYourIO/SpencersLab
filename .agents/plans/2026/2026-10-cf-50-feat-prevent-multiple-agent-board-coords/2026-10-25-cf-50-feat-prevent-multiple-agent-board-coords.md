# PLAN: agent-board-coord debounce gate (WeKan card #50) — FINAL (approval-round resolutions applied)
feature: 2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords

## Goal
The hourly scheduled launch of `agent-board-coord` is gated before any board action: a deterministic `!`-block script in a NEW scheduled-only command (`/pipeline-boards-hourly`) evaluates the OpenCode-session operand, and the agent evaluates the WeKan-Executing-list operand — via the **dev-boards MCP** (the user's ruling; server-side creds, none in the launch path) — only when the session operand says live. Fail-closed on either operand; manual `/pipeline-boards` runs stay byte-frozen and unguarded.

## Out of scope
- Loop files / `.agents/loops/` artifacts (approval answer: re-point the existing hourly UI task's prompt instead — Landing note).
- Any WeKan credentials in the script or repo (the MCP deployment holds them server-side; no env file, no creds step).
- Scheduler-side "skip-if-running" (verified absent); suppressing the session a SKIP still creates (one reporting turn, zero board actions — D10).
- Guarding `agent-coord` / the manual path / any change to `.rulesync/commands/pipeline-boards.md`, the boards skill flow, or `agent-board-coord` frontmatter (all byte-pinned by tests).
- Killing or interrupting a detected live session.

## Predicate — who evaluates what, when (D11/D16/D17)
| # | Session operand (`!`-block script, deterministic) | Board operand (agent turn, read-only dev-boards MCP) | Verdict | Reading |
|---|---|---|---|---|
| 1 | no live board-coord ⇒ `GATE: RUN` | never evaluated (short-circuit — the GATE itself has zero board dependency) | **RUN** | the common hourly case (the post-gate flow still needs dev-boards for pickup, like any run) |
| 2 | live ⇒ `GATE: LIVE <id>` | Executing empty ⇒ proceed | **RUN** | user's between-cards case; accepted narrow double-claim race (D11) |
| 3 | live ⇒ `GATE: LIVE <id>` | ≥1 card ⇒ stop | **SKIP** | both busy — the overlap this ticket exists to prevent; report names session id + card titles |
| 4 | live ⇒ `GATE: LIVE <id>` | check unavailable (MCP error / unresolvable list) ⇒ stop | **SKIP** | per-operand fail-closed — cannot prove the disjunct |
| 5 | detection failed ⇒ `GATE: SKIP <reason>` | never evaluated | **SKIP** | OQ2 fail-closed (session side can never be rescued by the board side) |
| 6 | crash-resume: no live session (past 15-min window), card stuck in Executing | never evaluated | **RUN** | Executing alone never blocks; intake-D11 resume check continues the folder |
| 7 | one-off manual via `/pipeline-boards` | — | **unguarded** | the guard exists only on the scheduled command; a live MANUAL coord session does count on rows 2–4 for later scheduled fires (past its grace) |

## Commands
- `bash tests/agent-board-coord/gate.sh` — new (agent-test): C01 session-side fixture matrix (t1..t10, `--json` live-envelope fixtures, `GATE_NOW_MS` fixed clock) + C02 surface greps incl. manual-path invariance (t11..t17). Written ONLY from fixture data — agent-test calls NO MCP (pinned; offline-deterministic suite).
- `bash tests/agent-board-coord/rulesync-surface.sh`, `bash tests/agent-board-coord/agents-md.sh` — must stay green; pin breakage ⇒ `validation_at_fault` hand-back, fix routed to the test session.
- `rulesync generate` (37.x PATH / npx ladder, skip-with-warning = intake-ticket t14 precedent) ×2 — second run no-op; sources + generated committed together.
- `npx --no-install aislop ci --changes` — 0 errors on touched files.
- Live controls (manual, recorded in Review notes — never CI): C01 — bare script against the workspace server, exit ∈ {0,1,2} with a valid marker; while this ticket's coord tree is fresh it must return `GATE: LIVE <coord-id>`. C02 — review uses READ-ONLY dev-boards calls (`list_boards` → AI-Dev; lists under `In Process`; `list_cards_in_list` on `Executing`) to confirm the board operand's resolution matches what the human sees on the board. Review has `dev*` MCP allowed (matrix), agent-test/dev do not need any MCP for this design.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Session-side gate: `scripts/agent-board-coord-gate.sh` (RUN/LIVE/SKIP, 15-min staleness + child rule, fail-closed) | S | 1 | [] | — |
| C02 | `/pipeline-boards-hourly` command: gate `!`-block + LIVE-branch dev-boards BOARD CHECK protocol (+ body pointer, rules lines, regenerate, landing note) | M | 2 | [C01] | Interface: the command's decision rule keys on C01's three stdout markers and exit states; the guarded path cannot ship before the detector exists. |

## Wave order
1. C01
2. C02

## Risks / assumptions
- **LLM-relayed decisions, two of them**: the SKIP report (row 3/4/5 after the agent reads the gate/LIVE state) and the board operand itself (rows 2–4) run as agent turns on deterministic evidence — the class D10 already accepted; the session side (row 1/5, the common case) stays fully deterministic. Command text minimizes the judgment: marker-keyed rules, read-only tool allow-list, explicit write-deny list.
- **Board-name drift in two surfaces**: `Executing`/`In Process`/`AI-Dev` now appear in both the boards skill and the hourly command. Mismatch fails CLOSED (unresolvable ⇒ skip), the safe direction; the boards skill remains the flow's authority.
- **Silence gap** (one child tool call > threshold ⇒ not-live ⇒ row 1 RUN during a real overlap) — `--threshold` tunable; residual documented in script + command comments.
- Probes still open (C01 evidence tasks): `GET /api/session` cursor pagination; `/api/session/active` semantics (`{"data":{}}` while busy, unresolved); `opencode api` ↔ the OpenChamber-scheduled server identity confirmation.
- `.rulesync/commands/` + `.rulesync/subagents/` edits and `rulesync generate` are ask-gated for dev — user approval prompts expected mid-C02 (precedent: the completed intake ticket, rulesync 37.0.0 on PATH).
- dev-boards live-status was evidenced this pass (tool catalog answers 25 tools; values `enabled: true` @ `wekan-mcp:v60`); if it drifts down, rows 2–4 fail-closed to SKIP, row 1 passes the gate but its post-gate pickup fails loudly at the MCP — the GATE itself never depends on the board.

## Resolved approval-round questions (no open questions remain)
- Rollout Q1 (creds) → **user override honored via D16/D17**: dev-boards MCP, split gate; no `~/.config/agent-board-coord-gate.env`, no creds anywhere.
- Rollout Q2 (landing) → **re-point the existing hourly UI task's prompt to `/pipeline-boards-hourly`** (hourly cadence, model `openrouter/qwen/qwen3.8-flash`, agent `agent-board-coord` — defaults confirmed keep); no loop file.
- Rollout Q3 (loop defaults) → moot.

## Landing note (user-owned steps, in order)
1. PR merges `cf-50-feat-prevent-multiple-agent-board-coords` → `main` (agent never merges/pushes — repo hard rule).
2. Edit the existing hourly OpenChamber scheduled task: prompt → `/pipeline-boards-hourly`; keep cadence `hourly`, model `openrouter/qwen/qwen3.8-flash`, agent `agent-board-coord`. No other task may keep a `/pipeline-boards` prompt (unguarded double-fire hazard — retire any duplicates).
3. First hour (or **Run now**): confirm the task's last-run session shows either a `GATE: RUN`-started claim, a `GATE: LIVE`→board-check proceed/skip, or a clean `GATE: SKIP` note — and that a manual `/pipeline-boards` session still starts with no gate line at all.

---

# ROUND 2 — dynamic session-origin (FINAL 2026-10-25: RESEARCH.md landed + batched round answered; round 1 above stands SHIPPED)

**Trigger (verbatim intent):** the hard-coded `SESSION_URL_BASE = https://openchamber--dev-thehackmeister-coder.dev.scifi.farm` in `.rulesync/skills/boards/SKILL.md` (Config constants) "should not be hard coded, but needs to be pulled dynamically. To a research run if /opencode isn't enough to help." — user feedback on card #50 (Review). This SUPERSEDES the intake ticket's D20 "copy verbatim; never re-derive" for that constant ONLY (DECISIONS D18-R2); every other D20 constant stays byte-exact.

**Goal (R2 — final)**
The boards-skill session-link mechanism (claim comment, `session` custom-field write-back, research-only result comment, drift check) resolves the OpenChamber origin at runtime; link shape stays exactly `$(SESSION_URL_BASE)/?session=<sessionID>`. Unresolvable (block self-probe, D22-r2) ⇒ the run PROCEEDS and writes the RAW session id in every link slot, RESULT-flagged (user ruling, D23-r2) — never a remembered/guessed host. One new chunk: C03 (folds minor-1 per user OQ-R3).

## Why the literal is structurally wrong (evidence, this replan)
- The literal is the **dev-cluster Coder**'s app host (`coder.dev.scifi.farm`, wildcard `*-coder.dev.scifi.farm` — `services/dev/prod/values.yaml` coder ingress block; intake research §10: `CODER_ACCESS_URL=https://coder.dev.scifi.farm` in `charts/coder/templates/secret-coder.yaml`), label order `{app}--{workspace}--{user}` (intake D20, user-browser-confirmed).
- Round-1 runs themselves happened in a **different workspace on the gpu Coder**: this tree's agent env carries `VSCODE_PROXY_URI=https://{{port}}--main--SpencersLab-Claud--thehackmeister-coder.spencerslab.com` (empirically present — `env` dump this pass) and `CODER_AGENT_URL=https://coder.spencerslab.com/`. A single stored origin cannot be right for both; only the running workspace knows its own public app origin.
- **And the literal was a DEAD HOST** (RESEARCH Contradiction 1): dev coderd answers `openchamber--dev-thehackmeister-coder.dev.scifi.farm` (single dash between `dev` and `thehackmeister`) with **400 — invalid application-url format** (the grammar needs `{app}--{workspace}--{owner}`, double-dash; the intake's recorded string dropped one dash in transcription). Every historical board link built from it is broken; card #50's `session` CF was re-pointed by coord to the derived 200-verified gpu link (2026-10-25, executed — comments stay frozen history). The dynamic mechanism is the correct fix for a class of defect this finding proves, not merely argues.

## Mechanism survey (requirement 2 — evaluated with evidence, not exhausted guesses)
| Candidate | Verdict (final) | Evidence |
|---|---|---|
| `opencode api get /api/info` / server API | **REJECTED as the origin** | The OpenCode server answers on `127.0.0.1` (round-1 AC3 probes: pid 57875, 127.0.0.1:49374); it knows nothing of the browser-facing OpenChamber origin. Carries the local server URL only. |
| Coder agent env `VSCODE_PROXY_URI` (`{{port}}`-template) | **SELECTED — RESEARCH-ENDORSED (RQ1 PASS)** | coderd-generated per workspace by source (RESEARCH [S1][S2]); both lab coders run the identical build v2.35.2+5c2838a ([S5][S6]); the derived agent-labelled named host 303-normalizes on BOTH coders with the `?session=` query preserved ([S12]); the agent label is parsed away for app slugs by design ([S3]) — keeping it is harmless and assumption-free (user ruling). |
| Repo prior art (coder wildcard plan 2026-09-28, dev values, wekan-mcp) | GROUNDING, not a runtime source | Documents wildcard formats/label orders and that the origin is deployment-specific; nothing in `services/` or `containers/` publishes the OpenChamber origin (repo-wide grep this pass). |
| OpenChamber served config / instance "public address" | **REJECTED — RQ2 = NO such setting** | Origins are browser-reported per integration event (`window.location.origin`, validated server-side; RESEARCH [S15]–[S17]); no stored instance address exists; the persisted Linear sessionOrigin file records historical browser origins (a banned source class); `connect-url` yields loopback/LAN only. Bonus mutual confirmation: OpenChamber's own integration link is exactly `${origin}/?session=<id>` — the pinned shape IS its native contract. |
| Coder CLI / agent-token API | **REJECTED** | Agent token rejected at user-scoped routes; `coder` CLI refuses the workspace-agent identity (2026-10-18 coder-workspace-rebuild friction, recorded; re-confirmed [S21]). |
| Skill tells the agent to run a shell/file recipe | **REJECTED by permissions** | `agent-board-coord` frontmatter: deny-all baseline; no `shell` allow; `read` allowed only for plans/skills paths — it can neither expand `$VSCODE_PROXY_URI` nor read `~/.config/openchamber/**`. The resolution must ride a carrier that CAN: the commands' `!`-blocks (D10 class — expand outside the agent permission flow, on the OpenChamber host, where both inputs live). |
| Port-label base (`{{port}}→<port>`) | **EVIDENCE-DEAD (RQ3)** | Named-app grammar makes the slug the native first-slot value ([S3]); port hosts need an active forward, owner visibility, 63-char label, and NXDOMAIN in the gpu DNS view today ([S12][S20]) — strictly inferior to UNRESOLVED. Never re-adopt as "simplification" without new evidence. |

**Research: RESOLVED.** `RESEARCH.md` landed 2026-10-25 (user-sanctioned hop executed): RQ1 PASS — env injected on every agent, both coders same build, derived host recognized 303 on BOTH ([S12]); RQ2 NO — nothing OpenChamber-side is more reliable or even reachable headlessly; RQ3 named-host wins outright. Material contradiction absorbed (Contradiction 1 → DECISIONS D18-r2 supersession + survey bullet above): the shipped D20 literal is a DEAD HOST (400 = malformed single-dash), every historical literal-built link was broken; card #50's `session` CF re-pointed by coord to the derived 200-verified link (executed 2026-10-25), comments frozen. Residual honest limits (dev-workspace env STRING source-inferred; human-LAN DNS view ≠ workspace view; authenticated leg unfetch-verifiable) are covered by: the block's self-probe (D22 r2), live control (b), and the first-dev-run landing observation. gpu DNS durability per user ruling: **exact records only** — new/renamed gpu workspaces need their own record; the probe + raw-id fallback degrades gracefully until it lands.

## Round-2 chunk table
| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C03 | Dynamic session-origin: `Session origin:` `!`-block (env derivation + self-probe) in BOTH board commands + boards-skill Config-constants rewrite (resolution contract, raw-id UNRESOLVED fallback, run-scoped consistency check) + regenerate + FOLDED minor-1 (LIVE-branch allow-list + t11 re-pin + nit-1 clarifier) | M | 3 | [C02] | Edits the command surface C02 created and re-pins the freeze set C02 shipped (t12); branches from round-1 final `72500166a`. |

Wave order: 1. C01 ✅ done · 2. C02 ✅ done · 3. C03 (research + batched round DONE → user approval → agent-test re-pin → dev → review → final whole-plan re-review).

## Commands (R2 — final)
- `CHUNK_BASE=72500166a bash tests/agent-board-coord/gate.sh` — t1..t10 HOLD (script untouched); t13/t15/t16/t17 HOLD; **t11 STRENGTHENED** (folded minor-1: allow-list window gains `list_swimlanes`/`list_lists`; `--threshold 0` pin widened to pair the on-the-host clarifier); t12 RE-PINNED (boards + manual-command carve-out from the freeze set); t14 RE-PINNED (scope allow-set gains the six round-2 surfaces); **t18/t19 NEW** (origin-block contract incl. probe strings + skill dynamic-contract/negative-literal — pin the block strings, NO concrete host pinned anywhere; absence-pin covers both the single-dash dead literal and any other `SESSION_URL_BASE = https://` literal). Written by the test session; red-before-C03: t18/t19 + re-pinned c12.
- `bash tests/agent-board-coord/rulesync-surface.sh` — c12 RE-PINNED (literal-VERBATIM sub-pin → absence + dynamic-resolution phrases); c8 scope allowance already covers the skill paths; everything else HOLD.
- `bash tests/agent-board-coord/agents-md.sh` — content pins UNCHANGED (AGENTS.md must byte-stand); c7 scope allow-set gains the round-2 paths (test-session edit).
- `rulesync generate` ×2 (2nd no-op) + `rulesync generate --check`; sources + generated (`.opencode/commands/pipeline-boards.md`, `.opencode/commands/pipeline-boards-hourly.md`, `.opencode/skills/boards/SKILL.md`) committed together. Never hand-edit `.opencode/`.
- `npx --no-install aislop ci --changes` — 0 errors.
- Live controls (manual, read-only, Review-notes recorded): (a) run the `Session origin:` snippet in the worktree shell ⇒ emits `https://openchamber--main--spencerslab-claud--thehackmeister-coder.spencerslab.com` (this workspace's own, lowercased); (b) `curl -sI` that base ⇒ 303 auth-redirect, **never 400** (400 = malformed derivation — the code that proved the old literal dead; the block's own probe checks this at every expansion); (c) dev-coder leg + human click-through are LANDING OBSERVATIONS (first dev run eyeball-compares block output vs the dashboard app link) — fetch cannot prove the authenticated leg.

## Out of scope (R2)
- Rewriting historical WeKan COMMENTS: card #50's old comments carry the dead literal — frozen history. (Its `session` CF was already re-pointed by coord 2026-10-25 — executed context, not C03 work.)
- Intake-ticket artifacts (runbook, research, plans of that folder) — historical records; no edits.
- The two [open] friction items (ask-gate-silence audit; glob-derived scope lists) — machinery follow-ups, not folded. (minor-1 IS folded per the user's OQ-R3 ruling.)
- Coder 2.35.4 advisory bump (GHSA-h58h-qvv5-xvwg, CVE-2026-55438 — RESEARCH [S23]): adjacent, single-user lab, `workspace_proxy:false` on both; belongs to renovate, separate concern.
- Any touch to `agent-board-coord`'s frontmatter/body (its `$(SESSION_URL_BASE)/?session=` token text survives verbatim — the redefinition lives in the skill), the gate script, `AGENTS.md`, permission surfaces (t12/t15/t16/t17 continue to guard these).

## Risks / assumptions (R2 — final)
- **Proven, not assumed**: cross-coder parity (same build + live 303 matrix, RESEARCH RQ1); the one source-inferred leg (a dev workspace's literal env STRING) closes itself at the first dev-coder launch — the block running there IS the mechanism exercising itself; landing observation records the eyeball check.
- **gpu DNS = exact records only** (user ruling): a new/renamed gpu workspace's derived host won't resolve for lab humans until its own split-horizon record is added; the block's self-probe turns that into `UNRESOLVED` ⇒ raw-id fallback (graceful, visible) instead of a dead link. No wildcard landing step is planned.
- **Re-opening the round-1-frozen manual command** (`/pipeline-boards`) is user-ruled (OQ-R1: both commands), not drift. Edits strictly additive; t13/t15/t17/t11 keep guarding every other byte.
- **Probe cost/determinism**: one `curl -m 5` per command expansion (both paths; hourly gate flow already tolerates a multi-second `!`-block); the probe never blocks a run — worst case is UNRESOLVED + raw-id links.
- **LLM-relayed use**: the agent copies the block's line (or the raw id on UNRESOLVED) — zero derivation judgment left to it. Same compliance class as D10/D16.
- The `openchamber` app-slug constant inside the block is a workspace-template convention (`charts/coder/coder-templates/*` `coder_app` slug; same class as the pinned `/?session=` path), not an origin — documented residual.

## Round-2 answers (batched question round 2026-10-25 — ALL ANSWERED; no open questions remain)
- OQ-R1 ⇒ both commands, named host, agent label KEPT, as research endorsed (D19-r2 final).
- OQ-R2/R4 ⇒ CHANGED from the plan's best guess: UNRESOLVED ⇒ run PROCEEDS and writes the RAW session id in every would-be link slot (user amendment of D13 scoped to the fallback branch only — D23-r2). "Unresolvable" defined precisely by the block itself: env absent ∨ `{{port}}` template missing ∨ derived host answers outside {200,30x,401,403} (incl. 400 malformed, 000 DNS/connect/timeout) — the block self-probes at expansion (≤5 s) and emits one deterministic line; the agent can't pre-write-curl (no shell — verified), the command-block can; chosen over no-probe because the probe kills the D20 defect class (dead/foreign host ⇒ fallback, never a broken link silently shipped). D22-r2 records it.
- OQ-R3 ⇒ minor-1 FOLDED into C03 (allow-list + t11 STRENGTHENED re-pin + nit-1 on-the-host clarifier). Deferred note updated (append-only) in DECISIONS.
- Research OQ1 ⇒ gpu wildcard DNS is NOT a landing step: exact records only; mechanism must not assume wildcard coverage (risk above + probe absorbs).
- Research OQ2 ⇒ executed by coord pre-finalization: card #50 `session` CF re-pointed to `https://openchamber--main--spencerslab-claud--thehackmeister-coder.spencerslab.com/?session=ses_e8ec41e70ffe1oeW8kKnugIfwF` (human-verified 200); old comments stay frozen. Recorded in DECISIONS as executed context.
- Research OQ4 ⇒ landing observation: first dev-coder run eyeball-compares block output vs the dashboard app link.
- New unknowns: none — research's four residual unknowns all map to probe-catch (DNS), landing observation (dev leg, human click), or unchanged-standing caveat (authenticated leg, already intake-era).

## Landing note (R2 user-owned additions, appended to the round-1 Landing above)
1. After the PR lands: first `/pipeline-boards-hourly` (or manual) run — eyeball the `Session origin:` line vs the OpenChamber dashboard's app link for the SAME workspace; they must agree modulo the parsed-away agent label ([S3][S4]). This is also the dev-coder leg's live close-out if that run happens there.
2. If a gpu workspace is ever created/renamed: add its exact split-horizon `*-coder.spencerslab.com` host record (user ruling: exact records only, no wildcard landing) — until then the block degrades to UNRESOLVED + raw-id links, which is visible, not silent.
3. Optional separately-tracked follow-up (NOT this ticket): coder chart 2.35.2→2.35.4 advisory bump ([S23]) — renovate's lane.
