# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Plan-of-record: `2026-10-24-feat-board-coord-intake.md`; evidence log:
  `…-research.md`; deferred user-owned execution: `…-board-automation-runbook.md`.
- Run tags are retired for THIS flow (kickoff data); the slug alone names
  card-driven runs.

## Decisions
- 2026-10-24 plan D1: `pipeline-kickoff` + `pipeline-models` source files
  stay UNTOUCHED. The `boards` skill gains a "Card-driven kickoff" section
  that replaces kickoff Q1–Q3 and the run tag for card-driven runs only;
  `agent-coord` keeps live questions + run tags. Alternatives rejected:
  editing kickoff (would rewrite the non-board flow the user didn't ask
  to change); duplicating the models size-mapping table (drift risk —
  boards references pipeline-models as the mapping authority).
- 2026-10-24 plan D2: custom fields are handled by EXTENDING
  `containers/wekan-mcp` with typed tools (user-confirmed intake decision);
  raw REST from the agent stays out of the design. Tool interface pinned
  in C01 (names are the C02/C03 contract).
- 2026-10-24 plan D3: `set_card_custom_field` is an upsert (attach-if-
  missing via whole-array card PUT), because v9.99's value route silently
  no-ops on unattached fields and REST create can't set `alwaysOnCard`
  (research §1–2). Whole-array race accepted on a single-agent board.
- 2026-10-24 plan D4: research-only detection = board **label** read
  (get_board + get_card.label_ids) — no new tools, no label writes by the
  agent; label creation is human-owned. Confirmed intake decision:
  research-only cards end at Ready for Review; Finished stays human-owned.
- 2026-10-24 plan D5: future-card checklist automation rides WeKan board
  RULES (`createCard` → `addChecklistWithItems`, verified to fire for
  REST-created cards), NOT image changes and NOT agent discipline;
  existing cards get the runbook's MCP backfill loop. Custom-field
  future-card coverage = `automaticallyOnCard` flag + D3 upsert.
- 2026-10-24 plan D6: image refs stay `:main` + `imagePullPolicy: Always`;
  redeploy = post-merge pod restart (user-owned). Pin-to-`:v<run>` is
  impossible pre-merge (tag published only after merge) and untracked by
  renovate — recorded as a deferred follow-up. `tests/dev-mcp-fleet/
  boards.sh` c5 (asserts `:main`) stays green.
- 2026-10-24 plan D7: existing tests are extended as a SUPERSET
  (agent-board-coord surface + agents-md scripts) so the upstream ticket's
  pinned contracts (five section titles, frontmatter, dev_boards*) keep
  holding while the new facts are added; the test session remains the
  single author.
- 2026-10-24 plan D8: no pytest harness is introduced for wekan-mcp (none
  exists, no test deps pinned); deterministic gate = py_compile +
  tool-registry statics; live round-trip = user acceptance post-merge
  (same ruling as the upstream ticket's prompt-contract chunks).
- 2026-10-24 plan D9: the Services checklist's 13 items are recorded from
  the live `ls services/` (verified 2026-10-24) in skill + runbook, and
  the runbook owns the maintenance hook; the test regenerates the list
  from the repo so drift fails loudly.

- 2026-10-24 human D20 (D13 follow-up, at approval): the residual session
  host is CONFIRMED by the user from their browser:
  `SESSION_URL_BASE = https://openchamber--dev-thehackmeister-coder.dev.scifi.farm`
  (Coder `coderd.appHostnameBuilder` label order is `{app}--{workspace}--
  {owner}`, workspace name lowercased — the user's string beat my
  guessed `{app}--{owner}--{workspace}` ordering; a fetch probe confirms
  the wildcard DNS/TLS is live (400 vs 404 = hostname recognized/routed,
  owner-auth beyond the probe). Session links in `session` custom-field
  values and research-only result comments are
  `$(SESSION_URL_BASE)/?session=<sessionID>` (path format verified in
  OpenChamber's router). The value lands verbatim in the boards skill as
  its single config constant.
- OQ1–OQ10 resolved 2026-10-24 in the batched round (D10–D19 below); the
  one residual item is the session-link base host (D13) — confirmed at
  approval.

## OQ-round resolutions (2026-10-24, human answers in the batched round)
- 2026-10-24 human D10 (OQ1 = guess confirmed): the `cf-<card-number>-`
  slug names EVERY surface — feature-folder suffix, worktree, branch, AND
  the coord session title. Boards skill uses the full slug everywhere;
  pipeline-conventions' `<type>-<slug>` folder pattern sees the type lead
  inside the slug as before (`2026-10-cf-<N>-<type>-<desc>`).
- 2026-10-24 human D11 (OQ2 = guess confirmed): resume the existing
  folder while its run is unfinished (`plan_status` not `complete`); a card
  re-picked AFTER its run completed starts a new sequential run
  `<slug>-1`, `<slug>-2`, …
- 2026-10-24 human D12 (OQ3 DEVIATION from best guess): the `models`
  custom field is DROPPED ENTIRELY. The board gets exactly TWO custom
  fields: `slug` and `session`. The Model(s) CHECKLIST is the sole
  model-routing input, read directly: exactly one checked → both tiers;
  several checked → largest=planning / smallest=code; only Local →
  `gpu-ai/qwen3.8-27b-q6` (mapping authority stays `pipeline-models`).
  The resolved routing lives in STATE.json `kickoff.models` + the claim
  comment instead. Post-plan write-back: set slug + session, prune
  unchecked items of all four checklists (the surviving checked Model(s)
  items ARE the on-card routing record). Rejected: single-select dropdown
  (cannot express several-checked), four checkbox fields (pollutes the
  board surface), the earlier text-record field (now unnecessary).
- 2026-10-24 human D13 (OQ4 DEVIATION): the `session` custom field stores
  a FULL URL, not the raw session id. Scheme resolved by targeted
  investigation (research §10): OpenChamber (the lab's session UI, served
  as the Coder app `openchamber` with `subdomain=true`,
  `share=owner`) addresses sessions as `<base>/?session=<sessionID>` —
  its deep-link router parses exactly that (`searchParams.get('session')`,
  electron main.mjs L3011-3021); Coder now lives on dev
  (charts/coder + custom-values/dev; wildcard `*-coder.dev.scifi.farm`,
  access url `https://coder.dev.scifi.farm`). RESIDUAL: the concrete
  app-host label (`openchamber--<user>--<workspace>-coder.dev.scifi.farm`
  pattern) is confirmed by the user at approval and recorded as a config
  constant in the boards skill; NO silent fallback to the raw id.
- 2026-10-24 human D14 (OQ5 = guess confirmed): research-only trigger is
  the `Research` LABEL only; Research-checklist items scope research for
  normal cards.
- 2026-10-24 human D15 (OQ6 DEVIATION — custom answer): research-only
  cards run an ITERATIVE loop, not a silent auto-mint: (1) initial
  `agent-research` round → (2) ONE batched follow-up question round to the
  user refining/directing further research (the round also carries the
  slug suggestion when the `slug` cf is unset) → (3) further research on
  the answers (continue the same research session via sessionID so
  context carries) → (4) post the comment (research-session URL + merged
  TLDR), do the D12-style write-back, move to Ready for Review. Default
  termination: at most one follow-up round, then wrap; residual open
  questions ride along in the final comment for the human's
  Finished-vs-Rework call.
- 2026-10-24 human D16 (OQ7 = guess confirmed): runbook Step 1 offers
  BOTH field paths (UI always-on-card backfill preferred; REST create +
  agent upsert fallback).
- 2026-10-24 human D18 (OQ9 = guess confirmed): label name `Research`,
  matched case-insensitively.
- 2026-10-24 human D19 (OQ10 = guess confirmed): research-only cards get
  the same write-back (slug + session URL; prune all four checklists to
  checked items) immediately before the Ready-for-Review move.
- 2026-10-24 human D17 (OQ8 DEVIATION): `:main` is NOT the end state —
  pin the immutable `:v<run>` immediately as a sequenced post-merge part
  of this ticket. Honest ordering (docker-build.yaml pushes only on merge
  to main/dev; a PR cannot publish the tag): M1 merge C01 → M2 pin-bump
  commit (services/gpu wekan-readonly + wekan-admin, services/dev boards
  → `:v<run>` of the M1 build; ArgoCD sync then recreates the MCPServer
  pods, replacing the old manual-restart step) → M3 verification
  (tools/list == 25). To keep M2 a one-line values edit, agent-test
  generalizes `tests/dev-mcp-fleet/boards.sh` c5 NOW to accept
  `wekan-mcp:main` OR `wekan-mcp:v<digits>`. Rejected: keeping :main
  (user vetoed); inventing a pin in the pre-merge PR (the tag cannot
  exist yet — honest sequencing over fiction).

- 2026-10-24 human D20 (D13 residual closed at approval): the session-link
  base is CONFIRMED from the user's browser:
  `SESSION_URL_BASE = https://openchamber--dev-thehackmeister-coder.dev.scifi.farm`
  — the Coder app-hostname label is `{app}--{workspace}--{user}` with the
  `-coder` wildcard suffix (workspace "Dev" lowercased), NOT my guessed
  `{app}--{user}--{workspace}` ordering; wildcard DNS/TLS is live (HTTP
  400/404 from the proxy on probe; `share=owner` auth is expected and not
  fetch-verifiable). Session links (the `session` custom-field value +
  research-only result comments) are exactly
  `$(SESSION_URL_BASE)/?session=<sessionID>` — the `/?session=` path is
  OpenChamber's own router format (research §10). The boards skill records
  the value verbatim as its single config constant; at first write-back the
  agent re-checks the link in an authenticated context and flags via RESULT
  if the constant drifted (never silently re-guesses).

## Deferred
- Board mutations + the M1–M3 pin sequence (see STATE.json `deferred`,
  runbook Step 0–4).
- 2026-10-24: OQ1–OQ10 closed in the batched round (D10–D19); D13 residual
  host closed by D20. Plan APPROVED 2026-10-24 (human, approval round).
