# PLAN: agent-board-coord intake/lifecycle redesign + AI-Dev board automation

feature: 2026/2026-10-feat-board-coord-intake
base: re-cut on origin/main `5e35ba6da` 2026-10-25 (STATE.json `kickoff.recut`);
D1–D20 unchanged except where this file's re-verification notes record deltas.

## Goal

Redesign the WeKan board-driven pipeline intake: card pickup walks
Rework → Not Started → **Low Priority** (top card first); standard card
checklists (Services / Type / Model(s) / Research) plus two board custom
fields (`slug`, `session`) replace the live kickoff questions — the Model(s)
**checklist is the sole model-routing input** (no `models` field, D12);
"Research"-labeled cards run an **iterative research-only loop** (research →
one batched follow-up round → further research → comment + write-back) and
end at Ready for Review; slugs are `cf-<card-number>-<type>-<desc>` naming
folder, worktree, branch and session title alike — run tags retire for
card-driven runs. Ships the wekan-mcp tool extension (on top of main's
login-mint client) and the sequenced post-merge image pin-bump (D17).

**Architecture:** the `boards` skill becomes the card-driven intake contract
(replacing `pipeline-kickoff` Q1–Q3 for board runs; routing reads the Model(s)
checklist through `pipeline-models`' size mapping); `agent-board-coord` and
`/pipeline-boards` reword to it; `containers/wekan-mcp` gains 5 typed tools;
live board mutations and the pin-bump are user-gated runbook/M-steps, gated
on the (still-missing) AI-Dev board AND on the dev `boards` MCP server
actually deploying (see prerequisites — verified absent on-cluster 2026-10-25).

## Scope

IN: wekan-mcp image extension (20→25 tools on main's login-mint base);
boards skill redesign; agent-board-coord body + /pipeline-boards deltas
(frontmatter adjudication: NARROW `dev_boards*` stays, D21); AGENTS.md +
permissions-matrix MERGE into main's diverged surfaces; board-automation
runbook (2 custom fields, 4 checklist rules, backfill, pin sequence).

## Out of scope

- Any mutation of the live WeKan board — user go-ahead via the runbook.
- Cluster mutations / ArgoCD syncs / making `mcp-boards` deploy (GitOps +
  dev-mcp-fleet fix-round in flight; user-owned).
- `pipeline-kickoff` / `pipeline-models` / other `pipeline-role-*` /
  `agent-coord` sources (D1); broad `dev*` for agent-board-coord (D21).
- AI-Dev board / bot account creation; renovate config changes (pinning
  makes the image renovate-tracked automatically).

## User-owned prerequisites / sequence

1. AI-Dev board structure incl. **Low Priority** list + **Research** label
   + bot membership (runbook Step 0).
2. **WeKan bot credentials behind main's wiring (re-cut delta):** the
   Bitwarden `wekan-mcp` LOGIN item is REAL (`custom-values/dev/prod-values.yaml`
   L35 UUID `d8e2b2ca…` — the old `dev-wekan-boards` placeholder prerequisite
   is SUPERSEDED). Remaining: the item's username+password are a valid
   password-based WeKan account AND the URI field points at
   `https://wekan.spencerslab.com`.
3. **`mcp-boards` deployment on dev (NEW residual):** the MCPServer CRD is
   ABSENT cluster-side as of 2026-10-25 (fleet CRDs playwright/renovate/
   searxng running ~5 min; no boards) despite the merged values entry —
   dev-mcp-fleet's C03 fix-round is in flight on main. The flow cannot run
   until `mcp-boards` is up and its pod authenticates (server fails fast on
   bad creds). Verify: MCPServer CRD `mcp-boards` + Running pod + the
   dev-boards tool round-trip.
4. Post-merge sequence (D17): **M1** merge C01 → CI publishes
   `wekan-mcp:v<run>`; **M2** pin-bump commit (gpu `wekan-readonly`+
   `wekan-admin` + dev `boards` refs → `:v<run>`; test t7 of
   `tests/services/dev-mcp-fleet.sh` pre-generalized by agent-test; after
   the pin, renovate's docker manager carries future bumps — precedent
   `renovate-mcp:v31`); **M3** verify tools/list == 25 on dev-boards AND
   gpu wekan-admin.

## Verified facts (new base `5e35ba6da` + branch `8ef6a8056`, re-verified 2026-10-25)

Evidence log `2026-10-24-…-research.md` (§1–9 WeKan v9.99 source at the
DEPLOYED tag — unchanged, re-confirmed live pod still `ghcr.io/wekan/wekan:
v9.99` — plus §10 resolutions and §11 new-base verification). Highlights:

- wekan-mcp on the new base: **exactly 20 registered tools (11 read + 9
  write)** — the launch message's "27 tools" is WRONG (grep + README +
  wekan-api SKILL all say 20; recorded D22). C01's 20→25 counts STAND.
  No custom-field / checklist-delete tools (grep: zero `customField` in
  server.py).
- `wekan.py` now supports **login-mint** (WEKAN_TOKEN precedence;
  WEKAN_USERNAME+WEKAN_PASSWORD → `POST /users/login` at startup + bounded
  refresh-on-401) — client verbs get/post/put/delete + `user_id` unchanged,
  so C01's tool designs are unaffected; `tests/containers/wekan-mcp-login.sh`
  (t1–t6, mock-server based, imports ONLY `wekan.py`) is the image-side
  regression gate C01 must keep green.
- dev `boards` values entry (`services/dev/prod/values.yaml` ~L409-440):
  `wekan-mcp:main` + `imagePullPolicy: Always`, env arrives ENTIRELY via
  the `wekan-mcp` Secret — `WEKAN_BASE_URL` (from the item's URI field via
  `bitwarden-uri` store — "base URL is data, not config", user decision
  2026-10-24) + `WEKAN_USERNAME` + `WEKAN_PASSWORD`. No `WEKAN_TOKEN` on
  dev; gpu keeps its token-only path (`services/gpu/prod/templates/
  secret-wekan-mcp.yaml` → `WEKAN_TOKEN`).
- main's `tests/services/dev-mcp-fleet.sh` t7 asserts dev boards image ==
  `ghcr.io/ownyourio/wekan-mcp:main` strictly — M2's generalization target
  (replaces the old `tests/dev-mcp-fleet/boards.sh` c5; that dir is GONE —
  the old ticket's `tests/agent-board-coord/` suite is ALSO gone; agent-test
  recreates from `git show 09696ae57:tests/agent-board-coord/…`, reachable).
- main's pipeline agents carry broad `dev*`; the ported agent-board-coord
  carries narrow `dev_boards*` (source L76). ADJUDICATED (D21): keep narrow.
- `permissions.md` lost the board-coord row and `overview.md` lost all
  board-coord mentions on main (grep: 0 matches) — C04 MERGES roster +
  pipeline bullet + matrix row back, keeping main's combined
  `dev-<service> …` table row.
- Live cluster (readonly-dev-kubernetes 2026-10-25): MCPServers present =
  kubernetes×2, playwright, renovate, searxng; **NO mcp-boards**.
  admin-global-wekan `list_boards` still → "Projects" only: AI-Dev absent.
- OpenChamber session-link constant unaffected by the base change — D20
  verbatim: `SESSION_URL_BASE =
  https://openchamber--dev-thehackmeister-coder.dev.scifi.farm` (Coder
  label order `{app}--{workspace}--{user}`), links
  `$(SESSION_URL_BASE)/?session=<id>`. Agents copy D20's string, never
  re-derive the label.
- `services/` = 13 folders (re-`ls` on new base — unchanged).
- WeKan API claims (research §1–6: custom-field endpoints, value no-op on
  unattached fields, DELETE checklist item, createCard→addChecklistWithItems
  rules, cardNumber/projection facts) verified at v9.99 — the deployed tag
  (home-cluster pod image re-checked 2026-10-25).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | wekan-mcp 5 typed tools (20→25) + `_slim_card` card_number/custom_fields + README/wekan-api parity — on main's login-mint client | M | 1 | [] | container interface; names pinned in the plan |
| C02 | `boards` skill redesign (pickup order, checklist-as-answers, slug/session cf, cf-slug/no-run-tag everywhere, iterative research-only, write-back, D20 URL constant) | M | 1 | [] | independent (interface pinned) |
| C03 | agent-board-coord body + /pipeline-boards deltas; frontmatter keeps narrow `dev_boards*` (D21) | S | 2 | [C02] | quotes skill sections |
| C04 | MERGE board-coord rows into main's diverged overview.md + permissions.md; AGENTS.md regen | S | 3 | [C03] | documents the settled surface |

## Wave order

1. C01, C02 (id order)
2. C03
3. C04
then user-gated: M1→M2→M3 + runbook Steps 0–3 (gated on board existence AND
mcp-boards deploy, prerequisite 3).

## Commands

- `bash tests/wekan-mcp/tools.sh` — new (agent-test): 25-tool registry (13
  read + 12 write), the 5 names, `_slim_card` additions, route strings,
  README + wekan-api parity (25; login-mint wording; stale VERSION/semver
  bullet gone — README's credential bullet is already login-mint-current).
- `bash tests/agent-board-coord/rulesync-surface.sh` — RECREATED by
  agent-test on the new base (old suite deleted; reference
  `git show 09696ae57:tests/agent-board-coord/rulesync-surface.sh`) as the
  superset: old c1–c8 (incl. narrow `dev_boards*` frontmatter contract +
  permissions.md board-coord row) + new OQ-round facts (Low Priority, four
  checklists, slug/session **without** models, `cf-`, `SESSION_URL_BASE`
  D20 literal, `?session=`, iterative research-only, no-run-tag, resume vs
  `-N`).
- `bash tests/agent-board-coord/agents-md.sh` — recreated analogously
  (merged-surface assertions: roster + pipeline bullet re-added; main's
  combined dev-<service> row KEPT verbatim).
- `bash tests/services/dev-mcp-fleet.sh` — unchanged except agent-test
  generalizes t7's boards image equality to `(main|v[0-9]+)` (enables M2);
  full-suite regression stays green.
- `bash tests/containers/wekan-mcp-login.sh` — unchanged; C01 regression
  (must stay green — it only touches wekan.py contracts C01 doesn't edit).
- `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py containers/wekan-mcp/wekan_mcp/wekan.py`
- `docker build containers/wekan-mcp` (local smoke; CI PR build authoritative).
- Live board walkthrough + 25-tool round-trip: user acceptance after M1–M3 +
  runbook (prompt contracts have no runtime test by design).

## Risks / assumptions

- Double-gated live acceptance: AI-Dev board absent AND mcp-boards CRD not
  yet deployed (dev-mcp-fleet fix-round in flight) — repo chunks unaffected
  (static gates), but the flow cannot run end-to-end until both land; if
  dev-mcp-fleet's fixes change the boards entry further, re-verify
  prerequisites 2–3 at M-time.
- M2 needs the human's `:v<run>` from the M1 CI run (honest sequencing).
- WeKan v9.99-pinned endpoint claims; re-verify per runbook maintenance hook.
- Whole-array customFields upsert races UI edits — single-agent board,
  documented.
- Comma-free checklist-option assumption (verified for all option sets).
- The launch message's "27 tools" was wrong; everything in C01 counts off
  the verified 20 (D22) — reviewers should trust grep over the handoff text.

## Resolved questions (batched round 2026-10-24, D10–D20; base-change
adjudications D21–D25 in DECISIONS.md)

OQ1/2/5/7/9/10 confirmed; OQ3→D12 (models field dropped), OQ4→D13/D20
(full URL, user-confirmed origin), OQ6→D15 (iterative research loop),
OQ8→D17 (immediate `:v<run>` pin, M1–M3). **No user decision was affected by
the re-cut** — deltas are facts (20 not 27; login-mint base; real UUID;
tests relocation; mcp-boards not yet deployed) and one adjudication
consistent with the standing ruling (D21 narrow `dev_boards*`).

## Landing note

Per repo hard rules, no merge/push to `main` happens in the run: chunks
commit locally on `feat-board-coord-intake`; M1/M2 land via user-owned PRs.
