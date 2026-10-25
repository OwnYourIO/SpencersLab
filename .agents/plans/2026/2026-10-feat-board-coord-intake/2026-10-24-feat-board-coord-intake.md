# PLAN: agent-board-coord intake/lifecycle redesign + AI-Dev board automation

feature: 2026/2026-10-feat-board-coord-intake

## Goal

Redesign the WeKan board-driven pipeline intake: card pickup walks
Rework → Not Started → **Low Priority** (top card first); standard card
checklists (Services / Type / Model(s) / Research) plus two board custom
fields (`slug`, `session`) replace the live kickoff questions — the Model(s)
**checklist is the sole model-routing input** (no `models` field, D12);
"Research"-labeled cards run an **iterative research-only loop** (research →
one batched follow-up round → further research → comment + write-back) and
end at Ready for Review; slugs are `cf-<card-number>-<type>-<desc>` and name
the folder, worktree, branch and session title alike — run tags retire for
card-driven runs. Ships the wekan-mcp tool extension and a **sequenced
post-merge image pin-bump** (`:v<run>` immediately, D17).

**Architecture:** the `boards` skill becomes the card-driven intake contract
(replacing `pipeline-kickoff` Q1–Q3 for board runs; routing reads the Model(s)
checklist through `pipeline-models`' size mapping); `agent-board-coord` and
`/pipeline-boards` reword to it; `containers/wekan-mcp` gains 5 typed tools;
live board mutations and the pin-bump are user-gated runbook/M-steps, gated
on the (still-missing) AI-Dev board.

## Scope

IN: wekan-mcp image extension; boards skill redesign; agent-board-coord body
+ /pipeline-boards deltas; AGENTS.md/rules sync; board-automation runbook
(2 custom fields, 4 checklist rules, existing-card backfill, pin-bump
sequence) authored now, executed later by the user.

## Out of scope

- Any mutation of the live WeKan board (fields, rules, checklists, labels,
  cards) — deferred to the user's explicit go-ahead via the runbook.
- Cluster mutations / ArgoCD syncs (GitOps applies; M-steps user-owned).
- `pipeline-kickoff` / `pipeline-models` / `pipeline-role-*` / `agent-coord`
  source files — run tags and live questions stay for the non-board flow (D1).
- The AI-Dev board / ai-dev-bot / Bitwarden `dev-wekan-boards` real UUID —
  upstream user-owned prerequisites, still pending (research §7).
- A `models` custom field — dropped per D12. New container images beyond
  wekan-mcp; `dev-boards` server wiring changes (unchanged; `dev_boards*`
  wildcard already covers new tools).

## User-owned prerequisites / sequence

1. AI-Dev board structure incl. **Low Priority** list + **Research** label +
   bot membership (runbook Step 0).
2. Bitwarden `dev-wekan-boards` real UUID behind the dev `boards-mcp`
   ExternalSecret (placeholder today).
3. ~~Approval of this plan incl. one residual confirmation~~ — **GRANTED
   2026-10-24**, residual host confirmed by the user (D20):
   `SESSION_URL_BASE = https://openchamber--dev-thehackmeister-coder.dev.scifi.farm`,
   session links `$(SESSION_URL_BASE)/?session=<sessionID>`.
4. Post-merge sequence (D17): **M1** merge C01 → CI publishes
   `wekan-mcp:v<run>` + `:main`; **M2** pin-bump commit — `services/gpu`
   `wekan-readonly` + `wekan-admin` and `services/dev` `boards` image refs
   → `:v<run>` (ArgoCD sync then recreates the MCPServer pods; supersedes
   manual pod restart); **M3** verify `tools/list` == 25.

## Verified facts

Evidence in `2026-10-24-feat-board-coord-intake-research.md` (WeKan **v9.99**
source at the deployed tag + shipped spec/api.py; repo facts at `09696ae57`;
§10 adds the OQ-round resolutions + session-URL discovery). Highlights:

- Typed custom-field REST endpoints exist; create IGNORES `alwaysOnCard` and
  the per-card value route no-ops on unattached fields → upsert tool needed
  (§1–2). Value-setting works for text fields; exactly TWO fields
  (`slug`, `session`) are created (§10 D12).
- `GET /api/cards/:cardId` returns the full card incl. `cardNumber`,
  `customFields`, `labelIds`; the by-list projection does not; list order ==
  board order (sort asc) → pickup = top-of-list then `get_card` (§3).
- Research-only detection: `get_board` labels + `get_card.label_ids`,
  case-insensitive name `Research` (D14/D18) — no new tools (§4).
- `DELETE .../items/:itemId` exists server-side → `delete_checklist_item`
  tool enables post-plan pruning of unchecked options (§5).
- Board rule `createCard → addChecklistWithItems` fires for REST- and
  UI-created cards; items comma-joined; no retroactive backfill; no
  custom-field rule action (§6).
- AI-Dev board absent as of 2026-10-24 (`list_boards` → "Projects") (§7).
- wekan-mcp: `:main`+Always today; `docker-build.yaml` publishes `:v<run>`
  only on merge to main/dev → pin must be a sequenced M2 (D17/§8).
  `tests/dev-mcp-fleet/boards.sh` c5 is generalized by agent-test to accept
  `:main` or `:v<digits>` so M2 is a values-only edit (plan D17).
- Coder is on **dev** (`coder.dev.scifi.farm`, wildcard
  `*-coder.dev.scifi.farm`); OpenChamber session URLs are
  `<base>/?session=<id>` (deep-link router evidence, §10).
- `services/` = 13 folders (backups, dev, gpu, gpu-ai, grow, home, infra,
  media, monitoring, personal, proxy-backup, proxy-local, proxy-remote).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | wekan-mcp custom-field tools (slug/session-ready) + checklist-item delete + richer card shape | M | 1 | [] | container interface; consumers only quote tool names, pinned in this plan |
| C02 | `boards` skill redesign (pickup order, checklist-as-answers incl. sole models input, slug/session cf fields, cf-slug/no-run-tag everywhere, iterative research-only loop, post-plan write-back, session-URL template) | M | 1 | [] | independent of C01 (interface pinned above) |
| C03 | agent-board-coord + /pipeline-boards deltas | S | 2 | [C02] | body/command quote the skill's section names and flow |
| C04 | AGENTS.md rules wording for the new flow | S | 3 | [C03] | documents the final surface; avoids regenerating twice |

## Wave order

1. C01, C02 (independent — id order, one agent at a time)
2. C03
3. C04
then user-gated: M1→M2→M3 (pin+verify) and runbook Steps 0–3 (board build).

## Commands

- `bash tests/wekan-mcp/tools.sh` — new (agent-test): the 5 tool defs +
  `_slim_card` additions + README 25-tool count + stale-VERSION-wording fix.
- `bash tests/agent-board-coord/rulesync-surface.sh` — extended (agent-test):
  original c1–c8 superset preserved + new facts (Low Priority, four
  checklists, `slug`/`session` fields **without** `models`, `cf-`,
  research-only iterative loop, no-run-tag, `?session=` URL template) on
  source AND generated surfaces; includes `rulesync generate` ×2 no-op.
- `bash tests/dev-mcp-fleet/boards.sh` — agent-test generalizes c5's image
  assertion to `wekan-mcp:(main|v[0-9]+)` (enables M2 without test rework);
  rest unchanged.
- `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py containers/wekan-mcp/wekan_mcp/wekan.py`
- `docker build containers/wekan-mcp` (local smoke when a daemon is up;
  CI PR build authoritative).
- Live board walkthrough + admin tool round-trip: **user acceptance after
  M1–M3 + runbook** (prompt-contract chunks have no runtime test by design —
  upstream-ticket ruling).

## Risks / assumptions

- AI-Dev board absence → nothing live-verifyable pre-merge; static gates +
  user acceptance post-merge (precedent upheld).
- M2 needs the human to supply the real `:v<run>` from the M1 CI run (the
  runbook leaves `<RUN>` placeholders — honest sequencing, no invented tag).
- `main` has advanced past the merge base (`ae9ecb053` touches
  pipeline-models — untouched here; no overlap with our files) — coord
  `git merge main` before wave 1.
- Whole-array `customFields` writes race concurrent UI edits — single-agent
  board, documented in the tool docstring.
- WeKan releases near-daily: claims are v9.99-pinned; re-verify per runbook
  maintenance hook.
- Comma-free checklist-option assumption (verified for all current sets).
- OQ6 loop default (one follow-up round) is the recorded assumption;
  changes land as skill text only.

## Resolved questions (batched round 2026-10-24 — full record DECISIONS D10–D19)

- OQ1 everywhere-`cf-` ✓ · OQ2 resume-unless-complete ✓ · OQ5 label-only ✓ ·
  OQ7 both backfill paths ✓ · OQ9 `Research` case-insensitive ✓ ·
  OQ10 research-only write-back ✓.
- **OQ3 DEVIATION:** `models` custom field dropped — Model(s) checklist is
  the sole routing input; resolved tiers go to STATE.json + claim comment;
  surviving checked items are the on-card record.
- **OQ4 DEVIATION (closed at approval, D20):** `session` cf = full URL
  `https://openchamber--dev-thehackmeister-coder.dev.scifi.farm/?session=<sessionID>`
  — user-confirmed origin, Coder label order `{app}--{workspace}--{user}`.
- **OQ6 DEVIATION:** research-only = iterative loop (initial research → one
  batched follow-up round incl. slug suggestion when unset → further
  research in the same session → comment + write-back → Ready for Review);
  default termination: one round, then wrap.
- **OQ8 DEVIATION:** pin `:v<run>` immediately via sequenced M1–M3; `:main`
  is transitional only.

## Landing note

Per repo hard rules, no merge/push to `main` happens in the run: chunks
commit locally on `feat-board-coord-intake`; M1 merge + M2 pin-bump land via
user-owned PRs.
