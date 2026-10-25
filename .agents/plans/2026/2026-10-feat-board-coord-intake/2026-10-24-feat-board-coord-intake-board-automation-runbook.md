# Board automation runbook — AI-Dev standard checklists + custom fields

**Execution owner: the user.** This runbook ships with the plan; every board
mutation below is DEFERRED until the user gives an explicit go-ahead (plan
decision D5). Steps 1–2 additionally require the AI-Dev board prerequisite to
be in place — as of 2026-10-24 `list_boards` (admin-global-wekan) still
returns only "Projects".

Access for the scriptable steps: `admin-global-wekan` MCP tools (gpu tier,
full write surface, same wekan.spencerslab.com instance the `dev-boards`
server will use). After C01 lands and the Step 4 M-sequence runs (M1 merge
→ M2 pin `:v<run>` → M3 sync), the
new tools (`create_custom_field`, `set_card_custom_field`,
`delete_checklist_item`, …) appear there too — the runbook can then run on
the gpu tier before `dev-boards` itself is connected.

## Step 0 — Gate: board structure (user-owned prerequisite, still pending)

On `https://wekan.spencerslab.com`:
1. Service/bot account `ai-dev-bot` (password-based; `WITH_API=true`
   instance) — token stored as Bitwarden `dev-wekan-boards` (the upstream
   ticket's placeholder must get a real UUID before `dev-boards` works).
2. Board **AI-Dev**, swimlane **In Process**, lists:
   **Not Started, Executing, Ready for Review, Rework, Finished, Low
   Priority** ← Low Priority is NEW for this redesign.
3. Board label named **Research** (any color). This label marks
   research-only cards (§ boards skill).
4. Add `ai-dev-bot` as a board member (write role).
5. Verify: `list_boards` shows AI-Dev for the bot token; `list_lists`
   returns the six lists; `list_swimlanes` returns In Process.

## Step 1 — Board-level custom fields: exactly TWO (`slug`, `session`)

Per DECISIONS D12 there is NO `models` custom field — the Model(s)
checklist (Step 2 rule) is the sole routing input. Both paths work; pick
one (both offered per D16/OQ7):

**Path A — UI (preferred; backfills every existing card automatically):**
- Board → Settings → Custom Fields: create `slug` and `session` — type
  **text**, tick **"always on card"** (+ "show on card"). The UI create
  goes through the hooked insert → `CustomFields.addToAllCards` attaches
  both fields to all existing AI-Dev cards (research §1).

**Path B — MCP (no per-card backfill, harmless):**
- `create_custom_field` for `slug` and `session` with
  `automatically_on_card=true`. REST create ignores `alwaysOnCard`
  (research §1) so existing cards don't get the field attached — the
  agent writes values via `set_card_custom_field`, which attaches-if-
  missing itself; future REST-created cards auto-attach via the flag.

`session` values are FULL URLs
`https://openchamber--dev-thehackmeister-coder.dev.scifi.farm/?session=<id>`
(D13/D20) — the boards skill carries that origin as `SESSION_URL_BASE`.

## Step 2 — Standard checklists on FUTURE cards (4 automation rules)

`create_rule` ×4 (trigger `createCard` with all matchers omitted → server
normalizes to `'*'`, so cards in ANY list/swimlane get them; rule engine
verified to fire for both REST-created and UI-created cards, research §6):

| rule title | action.checklistName | action.checklistItems (comma-joined; NO commas inside items) |
|---|---|---|
| Std checklists: Services | `Services` | `backups,dev,gpu,gpu-ai,grow,home,infra,media,monitoring,personal,proxy-backup,proxy-local,proxy-remote` |
| Std checklists: Type | `Type` | `feat,bug,debug,dep,refactor,chore,docs` |
| Std checklists: Model(s) | `Model(s)` | `Qwen Large,Qwen 27b,Qwen Flash,Local (gpu-ai)` |
| Std checklists: Research | `Research` | `None,Repo/codebase only,Upstream docs/API survey,Live cluster/board inspection,Deep research (agent-research)` |

Service list evidence: `ls services/` on 2026-10-24 → exactly the 13 above.
Verify after creation with `list_rules`.

## Step 3 — Backfill EXISTING cards

Rules don't touch existing cards. For each card in each list of AI-Dev
(swimlane In Process): `list_cards_in_list` → for each card,
`list_checklists` → `add_checklist` for each of the four standards that is
missing, with the full item list from the table above (items arrive
unchecked). Custom-field values: nothing to backfill — unset until the
agent's first write (upsert handles attach).

## Step 4 — Pin wekan-mcp IMMEDIATELY to the immutable `:v<run>` (D17, M-sequence)

`:main` is transitional only. The tag cannot exist before the merge
(`docker-build.yaml` pushes on merge to `main`/`dev`; PR builds never push),
so the pin lands as an explicit, sequenced post-merge step — not an
open-ended deferral:

1. **M1** — user merges the C01 commit → CI publishes
   `ghcr.io/ownyourio/wekan-mcp:v<RUN>` (+ rolling `:main`). Note `<RUN>`.
2. **M2** — pin-bump commit (user, or a tiny follow-up run on a fresh
   branch): set the three image refs to `:v<RUN>` —
   `services/gpu/prod/values.yaml` `wekan-readonly` + `wekan-admin`,
   `services/dev/prod/values.yaml` `boards`. Keep
   `imagePullPolicy: Always` (still correct for an immutable tag; the
   upstream test contract expects it). `tests/dev-mcp-fleet/boards.sh` c5
   was already generalized by this ticket's agent-test
   (`wekan-mcp:(main|v[0-9]+)`) — no test edit needed here.
3. **M3** — user merges M2 → ArgoCD syncs → the MCPServer CRD image change
   recreates the pods (no manual restart step).
4. Verify: `admin-global-wekan` tools/list shows the 25 tools incl.
   `set_card_custom_field` and `delete_checklist_item`; one
   `get_card`/`list_custom_fields` round-trip.
5. `dev-boards` (dev cluster) rides the same image; its first live use
   still waits on Step 0's `dev-wekan-boards` real UUID.

## Step 5 — Maintenance hooks

- New `services/` folder → update the Services rule
  (`update_rule` REPLACES the action wholesale — resend all fields) and,
  optionally, backfill existing cards' Services checklist.
- Option-text change (Type/Model(s)/Research) → same `update_rule`
  replacement + boards-skill edit lands via its own ticket.
- WeKan upgrades: the rules/fields/tools vocabulary was verified against
  v9.99 source; re-run the research-§ checks on any version bump
  (`ghcr.io/wekan/wekan` tag in `services/home/prod/values.yaml` block).
- Run `tests/` suites + `bash tests/wekan-mcp/tools.sh` after each WeKan
  minor upgrade (grep-level drift detector).
