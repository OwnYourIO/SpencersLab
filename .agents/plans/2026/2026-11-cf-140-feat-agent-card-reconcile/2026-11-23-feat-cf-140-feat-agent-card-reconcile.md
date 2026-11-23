# PLAN: card-runner pivot — agent-card-reconcile replaces the dispatcher; pipeline-locks + board-context retire
feature: 2026/2026-11-cf-140-feat-agent-card-reconcile

## Goal

Replace the `pipeline-locks` + `board-context` plugins with ONE hand-written deterministic
`card-runner` plugin, and pivot `agent-board-dispatch` into `agent-card-reconcile`: a reconcile
loop that each tick reads the board decision context plus live session status and detects
(a) finished runs / objective-met, (b) questions unanswered >15 min (record, move the card to a
new **Awaiting Answers** list, start the next task), (c) human card changes (bounded forward) —
so coordinators stop burning tokens and context on card mechanics. Grouped sibling **AD-73**
(card `_id` `qMMB5XRQpX9JXdbxZ`, inbound `related-to`) rides this plan: the doc/contract sweep
retiring the legacy `session` custom field (its board-level deletion stays owner-owned).

Everything below is grounded in `RESEARCH.md` (the consolidated bus; §7 contradictions are
settled — never re-derive), `REVIEW-existing-plugins.md` (B1–B3 blockers, M1–M8 majors), and the
four `EXPLORE-*.md` scouts. Evidence classes and round cites carry through the chunk files.

## Out of scope

- Merge to `main`, push, PR, deploy fixer — `Deployment` unchecked; commits stay local on
  `cf-140-feat-agent-card-reconcile`. Container CI validation is deferred to the owner's push
  (`docker build => no-daemon, CI-deferred` is the designed passing gate shape, cf-77).
- Webhooks on BOTH platforms (RESEARCH §6.1); the `format: yaml` wekan-mcp argument (§6.2 —
  `get_card_details` is already structured); LLM-judged "objective completed" (§6.3 — explicit
  signals only); per-card forge LABELS and any new WeKan custom field (§6.6, X6); any forge
  WRITE (O4 owner-gated); authoring a plugin-writing skill inside this ticket (§6.5).
- Board-structure mutations beyond the provision engine's dry-run + owner-confirmed apply:
  list creation, the AD-73 field deletion, checklist/rule edits, label creation and all
  OpenChamber scheduler-task acts (create/enable/fingerprint-approve/retire) are owner-owned.
- `question-notify`'s plugin file: stays owner-disabled and untouched (O2 records the posture;
  card-runner owns question DETECTION regardless, via the durable Form read — the research law).
- Follow-up cards (`Follow-up cards created` unchecked): deferred asks ride the Open questions
  section and the final summary — never new board cards.

## Commands

Validation is real for this repo (no unit-test suite beyond these, no docker daemon, no helm
surface in this ticket). Baselines measured 2026-11-23 on this worktree.

- drift: `npx --yes rulesync@37.0.0 generate --check` — RED at HEAD (AGENTS.md stale; C01
  repairs). Green from C01 on, after every chunk that touches `.rulesync/` sources.
  Idempotence: run `npx --yes rulesync@37.0.0 generate` twice; second run no-op
  (`git status --porcelain` empty).
- runtime tests: `node --test tests/opencode/*.test.ts` — baseline **393 pass / 0 fail**
  (measured). The count may move only with a recorded per-chunk rationale: a chunk that renames
  or replaces a plugin migrates coverage, it never silently drops it (retired test names get a
  named successor or a review-note rationale).
- shell contract suites (bash, repo root; per-chunk subsets in the chunk files):
  `tests/agent-board-coord/{gate.sh,rulesync-surface.sh,agents-md.sh}`,
  `tests/dispatcher/surface.sh`, `tests/noop-marker/surface.sh` (N1–N8),
  `tests/cf96-tz/surface.sh`, `tests/cf96-lifecycle/surface.sh`, `tests/agent-perms/surface.sh`,
  `tests/session-origin/script.sh` (b0–b6), `tests/wekan-mcp/{tools.sh,board-context.sh,
  card-details.sh,slug-stack.sh,dependencies.sh,skill-surface.sh,create-list.sh}`,
  `python3 tests/wekan-mcp/registry-parity.py counts|claims|rows`,
  `tests/wekan-board-provision/surface.sh`, `tests/provider-loops/surface.sh`,
  `tests/boards-deps/surface.sh`, `tests/cf106-noop/surface.sh`, `tests/handoff/surface.sh`,
  `tests/coord-inwork/surface.sh`, `tests/agent-narratives/surface.sh`,
  `tests/pipeline-models/surface.sh`, `tests/kickoff-branch/{script.sh,surface.sh}`,
  `tests/multi-repo/hourly-board-check.sh`, `tests/cf90-ledger/surface.sh`,
  `tests/cf96-coord/surface.sh`, `tests/cf96-siblings/surface.sh`, `tests/cf96-deploy/surface.sh`.
- slop: `npx --yes aislop@0.20.0 scan --changes` on touched files (the `aislop-gate` plugin
  auto-appends findings on edits; CI floor = score ≥80 + zero error-severity on touched files).
  Comments follow `comment-slop` (why, never what).
- provision engine: `python3 scripts/provision-board.py --fixture <snapshot.json> --dry-run`
  (offline, deterministic, zero board effect); the zero-action re-run invariant guards applies.
- container (C11 only): `docker build => no-daemon, CI-deferred` recorded honestly in
  `commands_run`; with `Deployment` unchecked the Forgejo `containers-build.yaml` proof defers
  to the owner's push/PR — the chunk says so, it never claims a build it cannot run.
- typecheck — CONDITIONAL, only if O1 rules yes and C20 ran:
  `npx --yes --package=typescript@<C20 pin> -- tsc --noEmit -p <C20 tsconfig>` (never bare
  `npx tsc` — the deprecated 2.0.4 stub trap, R1). The plan works either way: without it, type
  errors surface at runtime (today's status quo) and the 393-test runtime suite is the floor.

## Chunks

Sizes: S/M/L per pipeline-role-plan. L always alone. Twin law: every edit to an alias/twin pair
(`agent-coord*`, `agent-board-coord*`) and every `.rulesync/` source lands with its generated
mirror in the SAME commit.

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | AGENTS.md / overview.md drift repair (FIRST commit) | S | 1 | [] | gates every later `rulesync generate` — regen currently clobbers the cf-126 dispatcher paragraph |
| C02 | AD-73 sibling sweep: retire the legacy `session` field from live contract docs | S | 1 | [] | independent doc sweep (sibling `_id` `qMMB5XRQpX9JXdbxZ`); sequence after C01 only if a `.rulesync/` source edit becomes necessary |
| C03 | card-runner skeleton: plugin scaffold, cross-process once-mark, localIso re-home | M | 1 | [C01] | needs green regen before any source-adjacent work; once-mark + localIso are the surfaces C04 consumes |
| C04 | Absorb board-context into card-runner; fix symptom (a); delete board-context | L | 1 | [C03] | migrates onto C03's scaffold/once-mark/localIso; the injection fix is the wave's payload |
| C05 | CARD.yaml contract: schema home, coord writer step, plan-file map, three-home rule | M | 1 | [C04] | replaces the retired claim-time card-details block as the card's context home |
| C06 | agent-card-reconcile: agent + loop file + wake re-target + gate liveness set | L | 2 | [C01] | the reconciler is the wave-2 spine; wake/gate/N4/N8 re-pins land with it |
| C07 | boards skill Reconcile doctrine: tick loop, decision matrix, spawn contract | M | 2 | [C06] | doctrine cites the agent/loop C06 ships; B1/M2 matrix rows are pinned here |
| C08 | card-runner question hook: durable pending-question record | M | 2 | [C03] | plugin-side leg on C03's scaffold; consume-once + call-id tolerance live here |
| C09 | Awaiting Answers provisioning: skill spec bullet + engine ensure + fixtures | M | 2 | [C01] | provision-engine pair (skill + `scripts/provision-board.py`); apply stays owner-run |
| C10 | Question-flow wiring: breach + resume procedures, B1 decision-order guarantee | M | 2 | [C07, C08, C09] | joins doctrine (C07), the record (C08) and the list (C09) into the flow the card asks for |
| C11 | wekan-mcp additive reads: `list_card_activities` + `whoami` (container, CI-deferred) | M | 3 | [] | independent container chain; C12 consumes it capability-gated (degrade = snapshot-diff-only) |
| C12 | Card-change detection + bounded forwarding (`.pipeline/cards/` store, M6 bounds) | L | 3 | [C05, C07, C10] | forwards rewrite CARD.yaml (C05) and ride the run-state matrix + resume doctrine (C07/C10) |
| C13 | Forgejo awareness: branch→PR lookup, `Card:` trailer doctrine, forge record slot | M | 3 | [C12] | forge deltas forward through C12's bounded-forward machinery; record slot rides its store |
| C14 | Run registry + zombie firewall + registration-verb tools (B2/B3) | L | 4 | [C06, C08, C12] | registry joins session↔card for firewall + reconcile; question records and card records feed rows |
| C15 | Retire pipeline-locks: compaction re-home, commands, no-op predicate, T15 | L | 4 | [C14] | the registry must exist before the leases die (firewall + restart-resume replace them) |
| C16 | Re-pin sweep I: 25 subagent Compaction paragraphs + permission rows + mirrors | L | 4 | [C15] | rewords only after the implementation home moved, so pins name the true owner |
| C17 | Re-pin sweep II: boards skill lock doctrine, overview.md, dispatch retirement, N4/N8 | L | 4 | [C15] | same; carries the M7 owner-enforced single-scheduler statement (Q-B gated deletion) |
| C18 | Coord intake rewrite: no card-fetch expectation, four intake paths, MCP propose | M | 4 | [C14, C17] | intake wording references registration semantics (C14) and the rewritten doctrine (C17) |
| C19 | Owner handoff: board catch-up dry-run, loop-approval runbook, O6 probes, full sweep | S | 5 | [C18] | the card's final task; every owner leg in one runbook, schedule never claimed live |
| C20 | CONDITIONAL (O1=yes): tsc gate + vendored typescript-strict + plugin-lanes TS skill | S | 1* | [C01] | *runs early wave 1 when adopted (before C03) so every TS chunk is type-gated; skipped when O1=no |

## Wave order

1. **Wave 1 — context hygiene** (ships value alone: drift green, symptom (a) dead, CARD.yaml
   contract live): C01 → {C02, C03 (C20 if adopted)} → C04 → C05.
2. **Wave 2 — reconcile + question flow**: C06 → C07; C08, C09 (parallel with C06/C07); C10.
3. **Wave 3 — reconciler capabilities**: C11 (anytime), C12 → C13.
4. **Wave 4 — lock retirement + re-pins** (largest blast radius; deliberately last among code
   waves so every earlier wave tip keeps the proven lock system live): C14 → C15 → {C16, C17}
   → C18.
5. **Wave 5 — handoff**: C19.

**Resumability (P10 confirmed, cut-aware):** every wave tip is a coherent, suite-green,
committable state; a later run resumes at `STATE.json current_wave` with no rework of `done`
chunks. Wave 1 alone fixes both owner-visible injection symptoms' first class; waves 1–2 alone
deliver the reconcile + question pivot with locks still live (transition-coherent: wake targets
BOTH dispatcher and reconciler names); wave 3 is additive; wave 4 is the irreversible retirement
— an owner may hold the branch at the wave-3 tip indefinitely. RV's "prove out in production
between waves" cannot happen inside one run (no deploy, all scheduler tasks owner-disabled):
the proof gate becomes the owner's manual reconciler runs + the C19 handoff runbook before any
schedule is enabled.

## Risks / assumptions

- **Model routing (owner correction 2026-11-24 — STATE.json `kickoff.models` + DECISIONS.md are
  the authority, not the launch brief):** API tiers unchanged (coord/test/dev/chunk-review =
  `openrouter/qwen/qwen3.8-flash`; plan/final-review = `openrouter/qwen/qwen3.8-2.4t-a95b`);
  LOCAL tiers (explore/research) are back on `gpu-ai/qwen3.8-27b-radiance-tp2` — the card
  body's original ask — for all remaining local-tier work, i.e. the checked `Post Research`
  stage. This plan expects NO post-approval research round (RESEARCH.md §1–10 is comprehensive;
  the residual unknowns are owner gates O1–O6, ruled plan decisions, and shipping-build
  re-proofs R-1..R-12, which are chunk ACs, not research). If a batched-round answer opens a
  genuine research need, coord launches it on the tp2 lane with the recorded caveat:
  `pipeline-models` documents tp2 as parked at `replicas 0` — routing answers a LOUD 502,
  never a silent fallback; a 502 on a local-tier launch is reported to the owner, never
  quietly re-routed. **No chunk in this plan requires the tp2 lane as an unverified
  assumption**; everything post-approval (test writing, dev, reviews, handoff) runs on the
  proven API tiers.

- **B1 (blocker, pinned):** the question-paused branch precedes the dead-run branch in the
  reconcile decision order — a paused session stays busy forever (R3) and must never read as
  dead; degrade on a missed ask is conservative (do not spawn; flag owner).
- **B2/B3 (blockers):** the zombie firewall and the durable cross-process run registry ship in
  C14 BEFORE leases die in C15; the firewall's false-positive storm class (RV §2b.5: 8-row
  spurious `stolen` on a live claim) is designed out — idempotent one-shot stop text, never
  per-beat-source re-fires.
- **Two-process topology is a first-class question for every read** (RESEARCH §1.5): all state
  lives on the canonical-root filesystem + the shared db; ZERO `ctx.storage` guards in
  card-runner (grep-pinned); `/api/session/active` absence means "not here", never "idle";
  liveness floor is record timestamps (process-agnostic), active map a supplement.
- **M6:** change-forwarding must not become the new injector — re-write CARD.yaml, forward ONE
  line (<300 chars), hash-dedupe, coalesce, cap 5 per card then a human-visible flag (P3).
- **M7:** dropping leases makes single-scheduler an OWNER-enforced invariant — C17 states it in
  the boards skill + AGENTS.md, and C19's runbook makes task retirement an explicit owner leg.
- **~3.0 KB session-metadata PATCH limit** (RV m3): all reconciler session-record bookkeeping
  stays small; metadata writes are read-merge-write (whole-replace law).
- **Deployed-surface lag:** every new consumer leg is capability-gated with the family degrade
  law (probe `tools/list`; degrade, one retry, RESULT note; never a hard failure, never a
  stall). Shipping-build re-proofs R-1..R-12 are mapped to chunk ACs (R-1→C14, R-2→C08/C12/C14,
  R-3→C08, R-8→C08/C10, R-11→C20, R-4/R-5/R-9/R-10/R-12→C19 runbook or design law).
- aislop `complexity/file-too-large` on a big card-runner file is an accepted-debt class
  (the 2767-line precedent); warnings don't gate CI, errors + the floor do.
- Checklist-generation ambiguity is live (M3): the reconciler's spawn brief consumes checklists
  per the boards skill's Transition rule — cited, never restated.

## Ticket-folder map (what agents read)

This folder: the dated plan file (this), `STATE.json` (machine state; only coord writes),
`DECISIONS.md` (append-only rulings incl. P1–P10), `FRICTION.md`, `RESEARCH.md` (the bus —
read at run start), `RESEARCH-r1..r5` + `REVIEW-existing-plugins.md` + `EXPLORE-*` (deep
sources, on demand), `chunks/C*.md` (one per chunk). **`CARD.yaml`** (contract lands in C05):
the card this run holds — request text, checklists with tick state, labels, custom fields,
edges, slug stack — written by the coordinator at kickoff, refreshed by the reconciler on
detected human changes; every agent on a board run reads it BEFORE the chunk file (the
read-order line lands in `pipeline-conventions` in C05). C05 dogfoods it: this ticket's own
`CARD.yaml` + the sibling's `CARD-AD-73.yaml` land in this folder as the live example.

## Open questions (the batched round — best-guess answer FIRST, then impact)

Owner-gated (RESEARCH §8 O1–O6 + two new). Plan decisions P1–P10 are RULED in `DECISIONS.md`
and are NOT part of this round (veto there if you disagree).

1. **O1 — npm dev surface (tsc gate).** Best guess: **ADOPT** — run C20: pinned
   `npx --package=typescript@7 -- tsc --noEmit` + hand-written Node-shaped tsconfig +
   `@types/node` + `.gitignore` `node_modules/` (the repo's FIRST npm dev surface), vendor
   `microsoft/typescript-strict` (MIT, SHA-pinned, VENDORED.md pattern) + a small repo-local
   plugin-lanes TS skill; R-11's 10-second bare-tsc probe runs before Commands freeze; tsc
   stays plan-Commands-only (CI addition rides the final summary as a deferred ask).
   Impact if NO: C20 drops, type errors in card-runner surface at runtime (status quo); the
   393-test runtime suite stays the only floor.
2. **O2 — question-notify: re-enable vs absorb.** Best guess: **ABSORB detection into
   card-runner; leave question-notify disabled and untouched; breach/dead-run alerts push via
   the admin-HA tier** (the same channel the still-live reap alert uses), config-gated
   `haNotify`. Impact if re-enable instead: C08/C15 must add cross-plugin consume-once dedupe
   (double-push class) and the T15/no-op reader pins re-point; the phone channel state stays
   the owner's toggle either way. The research law stands regardless: card-runner owns
   question detection via the durable Form read.
3. **O3 — provision `Awaiting Answers` + `Timeout` lists, or accept the jsonl degrade as
   permanent.** Best guess: **PROVISION both** — C09 adds the engine spec bullet(s), C19 runs
   the dry-run and the owner applies at the Final Review stop (lists are human-owned). Impact
   if declined: both flows keep the designed jsonl-degrade + card-comment shape forever (the
   Timeout leg has run degraded for 5 weeks — proven survivable, weaker triage).
4. **O4 — Forgejo PAT minting.** Best guess: **DO NOT mint for this ticket** — every forge leg
   here is read-only and reads are credential-free (public repo). Impact: no forge writes
   anywhere; a later label/comment writer needs a mint + scope ruling first
   (`read:repository`+`read:issue` floor; on a public repo a wrongly-scoped token FAILS where
   no token succeeds).
5. **O5 — canonical PR home.** Best guess: **Forgejo prod (`git.spencerslab.com`)** is the
   card-link canonical surface (branches, CI and `origin` live there); GitHub stays the
   main-mirror; C13 ships `forge.baseUrl` config-defaulted to Forgejo prod so a flip is
   config-only. Impact: the split-brain trap (RESEARCH §4.4 — `pipeline-push-pr` pushes
   Forgejo but opens the PR on GitHub) means until this is ruled the forge leg's answers for
   GitHub-side PRs read `none`; if GitHub is ruled canonical, the config flips and the
   `pipeline-push-pr` PR leg stays unchanged.
6. **O6 — owner live-fire probe legs.** Best guess: **owner runs them at C19** (runbook
   handed over): WeKan (a REST card edit does NOT bump `modifiedAt` on the deployed pod;
   `?fields=activities&cardId=` answers scoped; the `disableExportAvatars`/disable-all-exports/
   `disableActivities` admin flags), Forgejo (public read + `/pulls/{base}/{head}` lookup +
   the label probe on a throwaway PR). Impact until run: C11/C12/C13 ship behind capability
   gates + degrade laws; each probe retires an assumed-not-verified cell (R-12).
7. **Q-A — the pipeline-dispatch model-literal conflict (C01).** The stale `overview.md`
   source carries the NEWER 2026-11-22 radiance ruling but the pre-cf-126 worker framing; the
   checked-in AGENTS.md carries the cf-126 dispatch framing with the OLDER strata-q4 literal;
   the shipped loop files say dispatch=strata-q4, worker=radiance. Best guess: **the merged
   doc mirrors the shipped loop files** (dispatch keeps `gpu-ai/qwen3.8-flash-next-strata-q4`;
   the 2026-11-22 radiance ruling applied to the worker; a dispatch flip stays gated on
   cf-126 C04 owner facts — model literals move only by fresh owner ruling). Impact if the
   ruling extends to dispatch: `pipeline-dispatch.md`'s model row flips too, rotating its
   fingerprint (owner re-approval) — C01 stays doc-only either way and records the choice.
8. **Q-B — retire `agent-board-dispatch` + `.agents/loops/pipeline-dispatch.md` in C17, or
   keep them frozen beside the reconciler (the pipeline-worker pattern)?** Best guess:
   **RETIRE both** (the reconciler supersedes; all four OpenChamber tasks are currently
   `enabled:false` so nothing live breaks; the owner's task-retirement leg rides the C19
   runbook; N4/N8 re-pin to TWO loop files: frozen worker + card-reconcile). Impact if kept:
   the wake-tracking list stays two-name, N4/N8 pin three loop files, and the M7
   double-scheduler surface is larger (an owner could enable dispatch AND reconcile).

Deferred asks riding the final summary (follow-up cards unchecked; NOT board cards): aislop
pin drift 0.20.0→0.22.3 (R1); the b6 parity-ladder gap for `pipeline-boards-pr.md`
(EXPLORE-agents §8.2); a vendored `opencode-plugin-v2` reference skill for the SECOND ticket
that touches plugin code (R2); tsc-in-CI (if O1 adopts); AD-73's board-level field deletion +
every O3/O4/O5/Q-B owner leg (C19 runbook).
