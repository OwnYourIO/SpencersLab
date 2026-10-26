# PLAN: Live session-origin resolution for launches without a `Session origin:` line — script + scoped grant (cf-52 friction follow-up)
feature: 2026/2026-10-bug-session-origin-no-line

## Round-2 pivot (batched answers, user 2026-10-26 — approval "Approve both")
OQ1 chose the LIVE-DERIVE FALLBACK, overriding the planner's docs-only best guess: a validated repo script (`scripts/session-origin.sh`) emitting the derived+probed origin (or UNRESOLVED) + a scoped shell grant on both coord variants — same class as the approved sibling's kickoff-mint grant. OQ2 yes (claim-once STATE.json `kickoff.session_origin`); OQ3 freeze card #52's cased URL, canonical casing decided inside the script's contract (D13); OQ4 answered in-session (audit: the 2026-10-26 probe ran via coord's interactive shell tool before the tool-surface change — recorded D11, the override formalizes exactly this capability); OQ5 defer; OQ6 type/slug stand; OQ7 base `b0c975bf6`. D1's contract verdict stands (today's derivation was out of contract; no-line is an undefined fourth antecedent) — only the RESOLUTION leg changed. See DECISIONS D10–D16.

## Goal
Give a board-coord launch that never expanded a board command (raw-chat "take the next card"; a restart-reinjected leg) a sanctioned way to resolve `SESSION_URL_BASE`: the run executes `scripts/session-origin.sh` at claim and treats its single emitted line exactly like the command block's `Session origin:` line — copy-verbatim resolved base, or the D23-r2 raw-id posture on UNRESOLVED. Replace cf-52's forbidden improvisation with the written capability the user chose; make the run's origin state claim-once, recorded, and restart-stable.

## Ground truth (unchanged, evidence in DECISIONS)
- Candidate (a) is already shipped: BOTH commands emit the line + probe (`pipeline-boards.md:13-14`, hourly `:34-35`; byte-identical ×4, t18-pinned; `e9f4f88ff` on origin/main). Commands stay byte-frozen to this ticket.
- No-line is NOT the defined "env absent" branch (three UNRESOLVED branches are expansion-shell env evaluations); the constant had no referent; "nothing is re-derived agent-side" + coord's then-envelope proved the ban deliberate (cf-50 D19 r2 (d), D22). Card #52's session CF + claim comment carry the improvised cased URL `https://openchamber--main--SpencersLab-Claud--thehackmeister-coder.spencerslab.com/?session=ses_e899def27ffeHg8Hl5wywFMluP` (live get_card 2026-10-26) — frozen history (OQ3).

## Mechanism — the script contract (C01) + the skill leg + grants (C02)
`scripts/session-origin.sh` (no arguments):
- Reads `$VSCODE_PROXY_URI`; derivation and probe are BYTE-EQUIVALENT to the command block's shared fragments: `sed 's/{{port}}/openchamber/' | tr 'A-Z' 'a-z'`, single `curl -s -o /dev/null -m 5 -w '%{http_code}' "$b/" || true`, recognition set `{200,301,302,303,401,403}`. Emits EXACTLY one stdout line in the block's own vocabulary: `Session origin: <derived-base>` or `Session origin: UNRESOLVED (<reason>)` with the block's three reasons (no Coder app-origin env / unexpected VSCODE_PROXY_URI shape / derived host answered <code>). OQ3 answer built in: the emitted host is LOWERCASED — the script emits precisely what the command block would.
- Verdict = the emitted line; exit 0 on both resolved and degraded verdicts (UNRESOLVED never blocks the run, D23-r2); exit 1 ONLY on caller misuse (any argument → still emits `Session origin: UNRESOLVED (script misuse: unexpected arguments)` so a mis-call degrades safely rather than stalls the claim).
- No-credentials-in-output: never echo the raw env value or any token; probe failure degrades to `000`/UNRESOLVED, never retries (one bounded curl per call). NO test seam (D16): the behavior suite drives the real curl through loopback-listener fixtures. A cross-surface drift pin (behavior suite b6): shared derivation/probe fragments must read identically across the script and the FOUR command files (extends cf-50's md5 ladder to five surfaces).
Skill amendment (`.rulesync/skills/boards/SKILL.md`, Config constants + kickoff bullet + consistency bullet, append-only):
- Resolution order for the run's `Session origin:` slot: (1) launch command expanded → its line, verbatim (canonical); (2) no line → run `bash scripts/session-origin.sh` ONCE at claim, its emitted line occupies the slot verbatim; the ban on free-hand derivation STANDS (never remembered/guessed/historical hosts; no agent-side reconstruction — coderd-rendered env via block-or-script only), reworded so t19/c12/i3 carry-set needles (`Session origin:`, `VSCODE_PROXY_URI`, `?session=`…) survive unchanged.
- Any UNRESOLVED (block's or script's) or a failed/denied script channel → existing raw-id posture + RESULT record (unchanged consumer bullets read through the definition — minimal contact).
- Claim-once state (OQ2): STATE.json `kickoff.session_origin` = the slot's value verbatim (base or `UNRESOLVED (<reason>)`); every later leg — incl. post-restart re-supply — REUSES it; only a run that established none resolves.
- Entry note: sanctioned manual launch is `/pipeline-boards` (emits the line); raw-chat launches resolve via the script.
Grants (C02): `- action: shell / resource: bash scripts/session-origin.sh* / effect: allow` appended to BOTH coord variants' frontmatter (glob shape without space so the zero-arg call matches — NQ1), regenerate mirrors; extend `pipeline-role-coord`'s grant-containment sentence to enumerate the script grants (grants exist ONLY for their named purposes, never anything else — i2's `opencode api`/`shell`/`own`/`never` window must survive the wording move; cf-50 D21 posture).

## Out of scope
- `.rulesync/commands/` + `.opencode/commands/` (byte-frozen; read-only fragment-parity grep only), `scripts/agent-board-coord-gate.sh`, agent BODIES (OQ5 deferred), AGENTS.md/`.rulesync/rules`, `.agents/plans/templates/`, STATE.json schema machinery, card #52 board values (frozen), `pipeline-kickoff`/`pipeline-models`/`pipeline-gates`/`pipeline-role-fuser`.
- Sibling concerns, cross-referenced only: tests/** edit perms (`2026-10-bug-tests-edit-perms` — near-zero collision; one line), branch-minting + the THIRD allow (`2026-10-bug-kickoff-mints-run-branch` — hard stack dependency, see Risks/D14).

## Commands
- unit: `bash -n scripts/session-origin.sh`
- unit: `bash tests/session-origin/script.sh` (b1..b6 behavior suite; offline-deterministic via LOOPBACK-LISTENER fixtures — real curl, NO test seam in the script (D16: a probe-override would be a forgery surface the block never had); red before C01)
- contract: `bash tests/session-origin/surface.sh` (text pins + grant splice + fragment-parity ladder, both trees; red before C02)
- regression (both-bases convention; stack base — see Risks): `CHUNK_BASE=b0c975bf6 bash tests/agent-board-coord/gate.sh && CHUNK_BASE=b0c975bf6 bash tests/agent-board-coord/rulesync-surface.sh && CHUNK_BASE=b0c975bf6 bash tests/agent-board-coord/agents-md.sh && CHUNK_BASE=b0c975bf6 bash tests/coord-inwork/surface.sh`, then the same four at default `BASE=HEAD`. At C01: siblings green untouched (C01 adds new files only). At C02: i4/c2/t17 hold against the sibling-landed three-allow state re-pinned to exactly FOUR (splice list + `+12/-0` from `f11bfcb85` across both stacked deltas, or re-based per agent-test), c8/t14/c7 carry this folder's FEATURE line (continue the siblings' numbering — never renumber), t19/c12/i1/i2/i3/c17/t11/t12/t13/t15/t16/t18 + agents-md content pins HOLD unmodified (i5/t12 stay green via the sibling's landed agents-sync carve — never re-cut it).
- live control (manual, Review-notes recorded, never CI): `bash scripts/session-origin.sh` in this worktree shell ⇒ emits `Session origin: https://openchamber--main--spencerslab-claud--thehackmeister-coder.spencerslab.com` (lowercased canonical; cf-50 AC7a precedent — block re-execution emitted this exact base).
- regen: `rulesync generate` ×2 (2nd no-op) + `--check` clean; sources + mirrors one commit.
- lint: `npx --no-install aislop ci --changes` → 0 errors.
- scope proof: C01 diff == {scripts/session-origin.sh, tests/session-origin/script.sh, gate.sh t14 one-arm widening (only if the landed sibling hasn't already covered a second `scripts/` file), this folder}; C02 diff == {boards src+gen, pipeline-role-coord src+gen, agent-coord.md + agent-board-coord.md src+gen (frontmatter only), permissions.md src+gen cell, tests/session-origin/surface.sh, c8/t14/c7 FEATURE lines + i4/c2/t17 re-pins, this folder}.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | `scripts/session-origin.sh` + behavior suite (`tests/session-origin/script.sh`) incl. five-surface fragment-parity ladder (+ one t14 scope arm if uncovered) | S | 1 | [] | — (adds new files; the only existing-suite touch is the t14 allow-list arm; every pin stays green) |
| C02 | Boards-skill resolution-leg + claim-once text + FOURTH scoped grant on the coord pair + regenerate + four-way re-pins (i4/c2/t17) + contract surface + permissions.md coord-shell cell | M | 2 | [C01] + GIT-STACK: `2026-10-bug-kickoff-mints-run-branch` C02 landed on the stacked base | C02's text names the exact command string C01's script accepts, and the frontmatter resource literal must equal the landed script path; the i4/c2/t17 re-pins target the sibling's post-land exactly-THREE state, and the permissions.md edit requires the sibling's landed t12/i5 carve |

## Wave order
1. C01 (script + behavior suite; siblings green — only the t14 allow-arm may move)
2. C02 (one coupled subsystem: contract text + grants + mirrors + re-pins land together — partial landing turns the stacked siblings' suites red)

## Risks / assumptions
- **HARD STACK GATE (D14):** C02 dev starts only after the sibling's C02 (`bash scripts/kickoff-mint-branch.sh *` grant + three-allow re-pins) is on the working base. On an un-landed sibling, C02 is blocked-by-stack, not failed — coord re-checks; landing order is user-owned (as with cf-52's precedent). tests-edit-perms ordering is immaterial (shared t12/i5 carve from either sibling suffices; FEATURE numbering continues whichever lands first).
- **Drift coupling:** the script is the 5th copy of the derivation/probe logic; the fragment-parity ladder (b6/s-check, comparing script vs the four command files' shared fragments) is the guard — a future command-block edit without the script lands red.
- **Grant blast radius:** `bash scripts/session-origin.sh*` executes any argument-suffixed call — contained by the script's own misuse refusal (exit 1 + degraded line) + contract text + reviewer's agents-sync permission audit (cf-52 D10 class).
- **t19/c12/i3 windows:** append-only wording inside pinned bullets; the 900ci UNRESOLVED/absent/shape/answered passage must survive — if honest wording genuinely breaks a window, STOP → RESULT (test-faulty escalation, coord asks user → test session re-pins; cf-52 posture), never self-edit sibling tests.
- **Test-phase bootstrap:** agent-test's `tests/**` write gap persists until tests-edit-perms lands — this ticket's test phase rides parent-passed grants (documented precedent), not folded.
- Interactive-shell precedent (D11): the formalization makes future no-line runs compliant; cf-52's historical line stays open→fixed by its own coord at landing (user-owned step).

## Open questions (round 2 — NEW gaps only, all with best guesses; none block C01)
- NQ1 exact grant resource glob: `bash scripts/session-origin.sh*` (no space — zero-arg call must match the whole-string matcher) vs sibling-style `... *` [BEST GUESS: the no-space form; verified by the C02 suite's literal-allow pin and one live `opencode` matcher control at review]. Impact: resource literal in 4 files.
- NQ2 permissions.md fold: update the coord shell cell + one drift-incident line in C02 (BEST GUESS: yes — the diff changes the matrix's truth; mirrors the sibling's ruling; safe post-sibling via the landed carve) vs. defer to a matrix-refresh ticket (Impact: two files' prose + freeze-carve usage).
- NQ3 UNRESOLVED-at-claim wording: board slots get the RAW id ONLY (reason lives in `kickoff.session_origin` + RESULT, not on the card) — BEST GUESS, mirrors D23-r2's existing posture; Impact: one skill sentence.
- NQ4 stack confirmation: kickoff-mints C02 lands before this ticket's C02 — BEST GUESS already assumed; user's landing call.

## Landing note (user-owned)
1. PRs land in the order you choose; C02 execution waits for the sibling's C02 on the base.
2. After merge: cf-52's coord re-statuses its FRICTION line 8 open→fixed pointing here.
3. First raw-chat board launch after landing: claim comment + CF carry the script-derived LOWERCASED URL, STATE.json `kickoff.session_origin` records it once, RESULT notes the script leg.
