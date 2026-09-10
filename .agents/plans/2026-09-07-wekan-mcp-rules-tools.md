# wekan-mcp: add automation-rules tools

Date: 2026-09-07
Status: rules tools committed (be26e907); template-variables addendum
implemented, pending commit. Both pending merge + CI rebuild.

## Context

Question: can the `wekan-admin` MCP server create rules on a board? Answer
was no — the server exposed 15 typed tools, none for rules, while WeKan's
REST API has supported board automation rules (IFTTT, issue #2674) since
before the lab's deployed version. Decision: extend the in-repo server with
full rules support (read + create + edit + remove).

## Ground truth (verified, not assumed)

- Rules REST endpoints verified in the **v9.99 tag** of wekan/wekan — the
  deployed image (`ghcr.io/wekan/wekan:v9.99`, chart 9.99.0 in
  `services/home/prod/Chart.yaml`):
  - `GET    /api/boards/:boardId/rules` → `[{_id, title, trigger, action}]`
  - `GET    /api/boards/:boardId/rules/:ruleId` → `{_id, title, trigger, action}`
  - `POST   /api/boards/:boardId/rules` body `{title, trigger, action}` →
    `{_id, triggerId, actionId}`; requires `trigger.activityType` and
    `action.actionType`; omitted trigger matching fields default to `'*'`
    server-side (normalizeTriggerDoc, #2674)
  - `PUT    /api/boards/:boardId/rules/:ruleId` body `{title?, trigger?, action?}`
    → `{_id}`; supplied trigger/action replace the stored doc wholesale
  - `DELETE /api/boards/:boardId/rules/:ruleId` → `{_id}` (removes rule +
    trigger + action)
  - Source: `server/models/rules.js` (route handlers), `server/rulesButton.js`
    (Meteor-method counterpart), `server/apiMiddleware.js` (`sendJsonResult`
    writes `data` directly as the JSON body with `code` as HTTP status — no
    envelope, so `WekanClient` needed no changes).
- Writes require board write access (the service user has it — it creates cards).

## Changes

1. `containers/wekan-mcp/wekan_mcp/server.py`
   - `_slim_rule` helper (trigger/action pass through — WeKan already strips
     internal fields server-side).
   - Read tools (both tiers): `list_rules`, `get_rule`.
   - Write tools (admin tier only via `_write_tool`): `create_rule`,
     `update_rule`, `remove_rule`. `remove_rule` docstring marks it
     DESTRUCTIVE (the one exposed destructive op; delete_board/delete_card
     etc. remain omitted). Module docstring updated to match.
2. `containers/wekan-mcp/README.md`
   - 15 → 20 tools; three new table rows + rules read rows; destructive-ops
     paragraph notes the `remove_rule` exception.
3. `skills/wekan-api/SKILL.md`
   - MCP section rewritten for the actual deployed shape: two privilege
     tiers (`wekan-readonly` / `wekan-admin` URLs + audiences), 20 tools,
     write tools admin-only. (The old single-`wekan`-endpoint text predated
     the admin/readonly split.)
4. `skills/wekan-api/references/rest-api-overview.md`
   - New "Automation rules" section (all 5 endpoints, payload shapes,
     wildcard normalization, trigger/action vocabulary pointers) + TOC entry.

## Addendum: template variables in rule actions (same day)

Follow-up question: do email rules support templates/variables? **Yes** —
verified in v9.99 `server/rulesHelper.js` (`buildRuleVars`/`substituteVars`,
issue #2475): `{name}` tokens in action text fields are expanded at rule
time, case-insensitively; unknown tokens are left untouched.

- Substituted fields: `sendEmail`'s `emailTo`/`emailSubject`/`emailMsg`,
  `addChecklist`/`addChecklistWithItems` checklistName(+items),
  `addSwimlane` swimlaneName, `createCard` cardName.
- Variables: `{cardname}`/`{cardtitle}`, `{cardnumber}`, `{description}`,
  `{duedate}` (only when set), `{listname}`, `{swimlanename}`, `{boardname}`,
  `{username}` (activity actor), `{date}`, `{time}`, `{datetime}`.
- Card-scoped vars need a card context (board-level scheduled/button rules
  leave them unexpanded). `sendEmail` needs server mail config (e.g.
  `MAIL_URL`); send errors are logged and swallowed.

Documented in:
- `skills/wekan-api/references/rest-api-overview.md` — variables table,
  semantics, sendEmail curl example.
- `skills/wekan-api/references/api-py-cheatsheet.md` — new "Automation
  rules" command section (was missing entirely).
- `containers/wekan-mcp/wekan_mcp/server.py` — one-line variable note in
  `create_rule`'s docstring so models know when authoring sendEmail rules.

## Validation

- `python3 -m py_compile` passes on all three `wekan_mcp` modules.
- Smoke test (venv with fastmcp 3.4.7 + httpx 0.28.1, stubbed WekanClient):
  - ADMIN tier: 20 tools registered; `list_rules`/`get_rule`/`create_rule`/
    `update_rule`/`remove_rule` hit the exact endpoints with the exact bodies
    above and shape responses correctly; empty `update_rule` returns
    `{updated: false, reason}` without calling WeKan.
  - READONLY tier (`WEKAN_MCP_READ_ONLY=true`): 11 tools; all write tools
    (incl. the three rules writes) absent from the catalog.
- No unit-test harness exists in this container (module import instantiates
  `WekanClient` against live env vars); final verification is post-deploy:
  `list_rules` on board `TrfngHQf8PWj9mnqC` (Projects), then a
  create → get → update → remove round-trip via the admin tier.

## Deploy path (post admin/readonly split)

- Both wekan tiers reference the rolling tag
  `ghcr.io/ownyourio/wekan-mcp:main` with `imagePullPolicy: Always` in
  `services/gpu/prod/values.yaml` — merge to `main` + CI build, then delete
  the wekan MCP pods to force a re-pull (same mechanism as the swimlane-id
  stage-1 rollout on 2026-09-07).
