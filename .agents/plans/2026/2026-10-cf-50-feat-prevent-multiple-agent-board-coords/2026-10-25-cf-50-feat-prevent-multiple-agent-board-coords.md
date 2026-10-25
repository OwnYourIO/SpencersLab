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

# ROUND 2 — dynamic session-origin (replan 2026-10-25; round 1 above stands SHIPPED)

**Trigger (verbatim intent):** the hard-coded `SESSION_URL_BASE = https://openchamber--dev-thehackmeister-coder.dev.scifi.farm` in `.rulesync/skills/boards/SKILL.md` (Config constants) "should not be hard coded, but needs to be pulled dynamically. To a research run if /opencode isn't enough to help." — user feedback on card #50 (Review). This SUPERSEDES the intake ticket's D20 "copy verbatim; never re-derive" for that constant ONLY (DECISIONS D18-R2); every other D20 constant stays byte-exact.

## Goal (R2)
The boards-skill session-link mechanism (claim comment, `session` custom-field write-back, research-only result comment, drift check) resolves the OpenChamber origin at runtime; link shape stays exactly `$(SESSION_URL_BASE)/?session=<sessionID>`. Fail-closed when unresolvable. One new chunk: C03.

## Why the literal is structurally wrong (evidence, this replan)
- The literal is the **dev-cluster Coder**'s app host (`coder.dev.scifi.farm`, wildcard `*-coder.dev.scifi.farm` — `services/dev/prod/values.yaml` coder ingress block; intake research §10: `CODER_ACCESS_URL=https://coder.dev.scifi.farm` in `charts/coder/templates/secret-coder.yaml`), label order `{app}--{workspace}--{user}` (intake D20, user-browser-confirmed).
- Round-1 runs themselves happened in a **different workspace on the gpu Coder**: this tree's agent env carries `VSCODE_PROXY_URI=https://{{port}}--main--SpencersLab-Claud--thehackmeister-coder.spencerslab.com` (empirically present — `env` dump this pass) and `CODER_AGENT_URL=https://coder.spencerslab.com/`. A single stored origin cannot be right for both; only the running workspace knows its own public app origin.

## Mechanism survey (requirement 2 — evaluated with evidence, not exhausted guesses)
| Candidate | Verdict | Evidence |
|---|---|---|
| `opencode api get /api/info` / server API | **REJECTED as the origin** | The OpenCode server answers on `127.0.0.1` (round-1 AC3 probes: pid 57875, 127.0.0.1:49374); it knows nothing of the browser-facing OpenChamber origin. Carries the local server URL only. |
| Coder agent env `VSCODE_PROXY_URI` (`{{port}}`-template) | **SELECTED (best guess, pending research)** | Present in the session's runtime env THIS pass (proven); Coder itself renders the host tail per deployment, so no label-order assumption; derived named host empirically recognized by coderd: `https://openchamber--main--spencerslab-claud--thehackmeister-coder.spencerslab.com` → `303 → auth-redirect?redirect_uri=https://openchamber--spencerslab-claud--thehackmeister-coder.spencerslab.com/` (probe this pass — coderd accepts the agent-labelled form and normalizes; matches the intake D20 label order). |
| Repo prior art (coder wildcard plan 2026-09-28, dev values, wekan-mcp) | GROUNDING, not a runtime source | Documents wildcard formats/label orders and that the origin is deployment-specific; nothing in `services/` or `containers/` publishes the OpenChamber origin (repo-wide grep this pass). |
| OpenChamber served config / instance "public address" | **UNRESOLVED → research RQ2** | `~/.config/openchamber/run/openchamber-3000.json` holds loopback bind only (probed); no env var; bundle grep found no `VSCODE_PROXY_URI`/public-URL env hook. Intake research §10 says OpenChamber integrations post session links "when the instance has a public address" — where that address comes from (config readable by the agent?) is unverified from here. |
| Coder CLI / agent-token API | **REJECTED** | Agent token rejected at user-scoped routes; `coder` CLI refuses the workspace-agent identity (2026-10-18 coder-workspace-rebuild friction, recorded). |
| Skill tells the agent to run a shell/file recipe | **REJECTED by permissions** | `agent-board-coord` frontmatter: deny-all baseline; no `shell` allow; `read` allowed only for plans/skills paths — it can neither expand `$VSCODE_PROXY_URI` nor read `~/.config/openchamber/**`. The resolution must ride a carrier that CAN: the commands' `!`-blocks (D10 class — expand outside the agent permission flow, on the OpenChamber host, where both inputs live). |

**Declared research need (yes, user-sanctioned hop):** the mechanism is grounded and agent-resolvable-by-construction on the launch path, but end-to-end reliability on the DEV-cluster coder (the instance whose host the intake D20 confirmed) + the human click-through + OpenChamber's own public-address mechanism are not provable from /opencode + this repo alone. `RESEARCH.md` must land BEFORE agent-test pins the derivation strings. Questions:
- **RQ1** Dev-cluster Coder parity: does a board-coord-capable workspace on `coder.dev.scifi.farm` inject `VSCODE_PROXY_URI` with the `{{port}}--…-coder.dev.scifi.farm` shape; does its coderd accept the agent-labelled named app subdomain (303-normalize like gpu's 2.35.2); is `*-coder.dev.scifi.farm` reachable + auth round-trip correct for an authenticated human via the public proxy-remote chain (plan-time internal probes: the dev-host family answers `400` — recognized-routed, auth-beyond-unfetchable; the gpu port-label form returned `000` without `--resolve` and `303` with it → local DNS-view quirk to re-verify from a human-side view)?
- **RQ2** OpenChamber native public-address: where does the "instance has a public address" used by its GitHub/Linear integrations come from (settings file/env/API an agent-side `!`-block could read)? If it exists and beats env-derivation, adopt it as the primary source (same fail-closed envelope).
- **RQ3** Port-label fallback (`{{port}}→3000`, run-state `port` as the source) vs named-app host: which survives coderd's subdomain proxy policy (port proxy gates on workspace-proxy RBAC vs the app's `share=owner`) — and does the deep link `/?session=<id>` render identically behind each?

## Round-2 chunk table
| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C03 | Dynamic session-origin: `Session origin:` `!`-block in BOTH board commands + boards-skill Config-constants rewrite (resolution contract, UNRESOLVED fail-closed, run-scoped consistency check) + regenerate | M | 3 | [C02] | Edits the command surface C02 created and re-pins the freeze set C02 shipped (t12); branches from round-1 final `72500166a`. |

Wave order: 1. C01 ✅ done · 2. C02 ✅ done · 3. C03 (after RESEARCH.md + batched OQ round → agent-test re-pin → dev → review → final whole-plan re-review).

## Commands (R2 additions)
- `CHUNK_BASE=72500166a bash tests/agent-board-coord/gate.sh` — t1..t10 hold (script untouched); t12 RE-PINNED (boards+manual-command carve-out); t13/t15/t16/t17 hold; t11 holds additively; **t18/t19 NEW** (origin-block contract + skill dynamic-contract/negative-literal). Written by the test session; red-before-C03: t18/t19 + re-pinned c12.
- `bash tests/agent-board-coord/rulesync-surface.sh` — c12 RE-PINNED (literal-VERBATIM sub-pin → dynamic resolution + negative literal); c8 scope allowance already covers the skill paths; everything else HOLD.
- `bash tests/agent-board-coord/agents-md.sh` — content pins UNCHANGED (AGENTS.md must byte-stand); c7 scope allow-set gains the round-2 paths (test-session edit).
- `rulesync generate` ×2 (2nd no-op) + `rulesync generate --check`; sources + generated (`.opencode/commands/pipeline-boards.md`, `.opencode/commands/pipeline-boards-hourly.md`, `.opencode/skills/boards/SKILL.md`) committed together. Never hand-edit `.opencode/`.
- `npx --no-install aislop ci --changes` — 0 errors.
- Live controls (manual, read-only, Review-notes recorded): (a) run the `Session origin:` snippet in the worktree shell → base matches this workspace's coder app host, lowercased; (b) `curl -sI` that base → coderd recognizes (303/401-family, NOT NXDOMAIN/404) — gpu-side proof already in this plan's survey; dev-side leg rides RQ1.

## Out of scope (R2)
- Rewriting historical WeKan artifacts: card #50's existing claim/write-back comments carry the old literal — left as history; the new consistency check compares THIS run's writes only.
- Intake-ticket artifacts (runbook, research, plans of that folder) — historical records; no edits.
- The deferred minor-1 re-pin (LIVE-branch allow-list `list_swimlanes`/`list_lists` + t11) and the two [open] friction items (ask-gate silence audit; glob-derived scope lists) — join ONLY if the user opts in (OQ-R3).
- Any touch to `agent-board-coord`'s frontmatter/body (its `$(SESSION_URL_BASE)/?session=` token text survives verbatim — the redefinition lives in the skill), the gate script, `AGENTS.md`, permission surfaces (t12/t15/t16/t17 continue to guard these).

## Risks / assumptions (R2)
- **Cross-coder parity assumption**: `VSCODE_PROXY_URI` + named-app normalization assumed present on the dev-cluster coder (RQ1). If research kills it, C03's documented fallback (port-label base from the run-state port) keeps the same contract envelope; test pins re-pointed, not re-guessed.
- **Re-opening the round-1-frozen manual command** (`/pipeline-boards`) is deliberate per the user's request (OQ-R1 carries the hourly-only alternative with its manual-link casualty). Edits strictly additive; t13/t15/t17/t11 keep guarding every other byte.
- **LLM-relayed use**: the agent copies the block's line into links (token handling, no derivation judgment left to it); UNRESOLVED posture is mechanical. Same compliance class as D10/D16.
- The `openchamber` app-slug constant inside the block is a workspace-template convention (like the pinned `/?session=` path), not an origin — documented residual.

## Open questions (R2 — batched round; best guesses in the plan, work continues on them)
- **OQ-R1 (mechanism carrier + host form)** — best guess: identical `Session origin:` `!`-block in BOTH commands, named-app host (`{{port}}→openchamber` slug). Alternatives: (a) hourly-only — manual runs fail-closed on links (keeps round-1 manual freeze absolute); (b) port-label host `{{port}}→<run port>` — trades the app-slug constant for the 3000/port-file and a uglier human host; (c) extend the gate script stdout with an `ORIGIN:` line — scheduled-only + touches the pinned C01 contract. Impact: which surfaces re-pin; manual-path freeze story; human-visible host.
- **OQ-R2 (fail-closed posture when UNRESOLVED)** — best guess: proceed with card work, write NO session links, flag via RESULT `open_questions`. Alternatives: skip the whole write-back; write the raw session id (rejected — violates D13's never-raw rule). Impact: card-record completeness off-coder; drift-check wording.
- **OQ-R3 (fold minor-1?)** — scope option FOR THE USER: fold the deferred minor-1 (`pipeline-boards-hourly` LIVE-branch allow-list += `list_swimlanes`/`list_lists` + t11 re-pin + the `--threshold 0` "on the host" nit-clarifier — SAME command surface C03 already edits, saves one ticket) into C03, or keep it separate. **Best guess: keep separate** (scope discipline; C03 already re-pins t11-adjacent checks — folding would blend a user-confirmed re-pin into a contract change). Impact: C03 blast radius + one fewer ticket.
- **OQ-R4 (claim comment without an origin)** — best guess: omit the session line from the claim comment (run identity still rides slug + plan folder + the card id). Alternative: defer claiming until origin resolves (would stall the board flow on non-coder launches). Impact: Card-lifecycle wording.
- **OQ-R5 (which instance do humans actually click?)** — best guess: irrelevant BY CONSTRUCTION once dynamic (each run links to its own instance — a decisive advantage over ever choosing between gpu/dev hosts); research RQ1 confirms parity. Impact: none on the mechanism; settles any residual worry about links that used to point at a foreign instance.
