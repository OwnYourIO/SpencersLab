# Board automation runbook — AI-Dev standard checklists + custom fields

**Execution owner: the user.** This runbook ships with the plan; every board
mutation below is DEFERRED until the user gives an explicit go-ahead (plan
decision D5). Steps 1–2 additionally require the AI-Dev board prerequisite
(Step 0) to be in place — re-verified 2026-10-25: `list_boards`
(admin-global-wekan) still returns only "Projects".

Base note (re-cut 2026-10-25): the `dev-boards` MCP server's credential
wiring is main-canonical — Bitwarden LOGIN item **`wekan-mcp`** (real UUID
`d8e2b2ca-792d-4e0a-86ae-b4ed0122c21a` in `custom-values/dev/prod-values.yaml`),
ExternalSecret `services/dev/prod/templates/secret-wekan-mcp.yaml`
(username + password + URI field → `WEKAN_USERNAME`/`WEKAN_PASSWORD`/
`WEKAN_BASE_URL`, login-mint in-pod). The old-base `dev-wekan-boards`
placeholder + `WEKAN_TOKEN` approach is SUPERSEDED — see DECISIONS D23. The
`boards` MCPServer is also not yet deployed cluster-side (D23 residual).

Access for the scriptable steps: `admin-global-wekan` MCP tools (gpu tier,
full write surface, same wekan.spencerslab.com instance the `dev-boards`
server targets). After C01 lands and the Step 4 M-sequence runs (M1 merge
→ M2 pin `:v<run>` → M3 sync), the
new tools (`create_custom_field`, `set_card_custom_field`,
`delete_checklist_item`, …) appear there too — the runbook can then run on
the gpu tier before `dev-boards` itself is connected.

## Step 0 — Gate: board structure + bot account (user-owned prerequisite, still pending)

On `https://wekan.spencerslab.com`:
1. Password-based bot account (`WITH_API=true` instance) whose username +
   password are the values stored in the `wekan-mcp` Bitwarden LOGIN item
   (best-guess name `ai-dev-bot`), and whose **URI field** is
   `https://wekan.spencerslab.com`. `dev-boards` logs in as this user —
   verify mint works: a live `dev-boards` `list_boards` call once its
   MCPServer is deployed. (The GPU `wekan-readonly`/`wekan-admin` servers
   use the token path — a long-lived bearer from the same login; mint one
   via `POST /users/login` if not already stored, and note re-mint does
   NOT revoke old tokens, issue #1437.)
2. Board **AI-Dev**, swimlane **In Process**, lists:
   **Not Started, Executing, Ready for Review, Rework, Finished, Low
   Priority** ← Low Priority is NEW for this redesign.
3. Board label named **Research** (any color). This label marks
   research-only cards (§ boards skill).
4. Add the bot as a board member (write role — REST create-rule +
   custom-field writes need board WRITE access).
5. Verify: `list_boards` shows AI-Dev for the bot; `list_lists` returns
   the six lists; `list_swimlanes` returns In Process.
6. Dev-cluster residual (D23): deploy + health of the `mcp-boards`
   MCPServer is a separate user-owned follow-up on the dev-mcp-fleet
   track (absent as of 2026-10-25); the pipeline's live leg (`dev-boards`)
   can't run until it exists. Repo-side chunks are NOT gated on it.

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
   upstream test contract expects it). `tests/services/dev-mcp-fleet.sh`
   t7 (dev-boards image equality) was already generalized by this
   ticket's agent-test to `wekan-mcp:(main|v[0-9]+)` — no test edit needed
   here. After the pin, renovate's docker manager tracks further
   `:v<run>` bumps (precedent: `renovate-mcp:v31`).
3. **M3** — user merges M2 → ArgoCD syncs → the MCPServer CRD image change
   recreates the pods (no manual restart step).
4. Verify: `admin-global-wekan` tools/list shows the 25 tools incl.
   `set_card_custom_field` and `delete_checklist_item`; one
   `get_card`/`list_custom_fields` round-trip.
5. `dev-boards` (dev cluster) rides the same image; its first live use
   waits on Step 0 items 1/6 — valid bot credentials in the `wekan-mcp`
   LOGIN item (real UUID already wired) AND the `mcp-boards` MCPServer
   being deployed (D23 residual, dev-mcp-fleet track).

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
