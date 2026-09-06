# WeKan REST API Overview

Endpoint reference for the current WeKan REST API, distilled from the wiki (`REST-API-*` pages), the repo's `docs/API/*.md`, the generated Redoc HTML, and `api.py`. **This is version-lagged.** For anything critical, verify against `models/*.js` and `api.py` for your pinned WeKan version.

## Table of contents

1. [Base conventions](#base-conventions)
2. [Login and users](#login-and-users)
3. [Boards](#boards)
4. [Board members and roles](#board-members-and-roles)
5. [Lists](#lists)
6. [Swimlanes](#swimlanes)
7. [Cards](#cards)
8. [Checklists and checklist items](#checklists-and-checklist-items)
9. [Card comments](#card-comments)
10. [Custom fields](#custom-fields)
11. [Labels](#labels)
12. [Integrations (webhooks)](#integrations-webhooks)
13. [Attachments](#attachments)
14. [Admin and global settings](#admin-and-global-settings)
15. [Error handling patterns](#error-handling-patterns)

## Base conventions

- **Base URL**: your WeKan root, e.g. `https://boards.example.com`. Endpoints below are relative to that.
- **All authenticated requests** send `Authorization: Bearer <token>`.
- **All write requests** send `Content-Type: application/json` and a JSON body.
- **Server-side flag**: WeKan must be started with `WITH_API=true`, or every REST call returns an authentication error.
- **No pagination**. List endpoints return the full array.
- **No documented rate limiting**. Add client-side backoff yourself if hitting a slow board.
- **HTTP 200 does not mean success.** Many routes return 200 with an embedded error object. Parse the body.

## Login and users

### `POST /users/login` — obtain a bearer token (one-time)

This skill assumes the caller has already done this once and exported the resulting token as `WEKAN_TOKEN`. Documented here so you can help them do it if they haven't.

No auth on the endpoint itself. Use JSON — **form data is documented as broken** ("DOES NOT WORK! Please use As JSON example below!").

```bash
curl -X POST https://boards.example.com/users/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"s3cret"}'
```

Response:

```json
{
  "id": "wA8Ekjr5c9pDfSjaG",
  "token": "yA7l6vJ2...",
  "tokenExpires": "2026-10-17T12:34:56.789Z"
}
```

Notes:
- `username` and `password` are **case-sensitive**.
- `email` may be substituted for `username`.
- Token lifetime is governed server-side by `ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS` (default 90 days). One login → one long-lived token that can be reused across many sessions and scripts.
- **Logging in again does not invalidate the previous token** (issue #1437). Old tokens remain valid until they expire. Practical consequence: you cannot rotate a leaked token by re-logging-in — an admin must disable/re-enable the user, or the tokens must be cleared in Mongo directly.
- **LDAP/OIDC-only accounts fail here.** Use a password-based service account.

### `POST /users/register` — public self-registration

Only works if self-registration is enabled server-side. Body: `{ "username", "email", "password" }`.

### `POST /api/users` — create a user (admin)

Admin-only. Body includes `username`, `email`, `password`, and typically `fromAdmin: true`.

### `GET /api/users` — list users (admin only)

Returns array of `{_id, username}`.

### `GET /api/users/:id`

Returns full user document.

### `GET /api/user`

Returns the currently logged-in user (based on the bearer token).

### `PUT /api/users/:id`

Perform an action on a user. Body: `{ "action": "disableLogin" | "enableLogin" | "takeOwnership" }`.

### `DELETE /api/users/:id`

Deletes a user. Historically destructive — verify behavior on your version (issue #1289).

### `GET /api/users/:id/boards`

Boards this user is a member of.

## Boards

### `GET /api/boards/:id`

Full board document, including labels, members, permission.

### `POST /api/boards`

Create a board. Admin permission required for arbitrary `owner`; otherwise owner is inferred.

```json
{
  "title": "Q4 Roadmap",
  "owner": "wA8Ekjr5c9pDfSjaG",
  "isAdmin": true,
  "isActive": true,
  "isNoComments": false,
  "isCommentOnly": false,
  "permission": "private",
  "color": "belize"
}
```

Valid colors: `belize`, `nephritis`, `pomegranate`, `pumpkin`, `wisteria`, `midnight`, `moderatepink`, `strongcyan`, `limegreen`, `midnight`, `dark`, `relax`, `corteza`, `clearblue`, `natural`. (Set has grown over time; verify against your version.)

Response: `{ "_id": "<newBoardId>", "defaultSwimlaneId": "..." }`.

### `DELETE /api/boards/:id`

Deletes the board.

### `POST /api/boards/:id/copy`

Duplicate a board.

### `GET /api/boards/:id/export`

Returns the full board JSON for backup/migration.

### `GET /api/boards/:id/attachments`

Returns all attachments on the board:

```json
[
  {
    "attachmentId": "...",
    "attachmentName": "spec.pdf",
    "attachmentType": "application/pdf",
    "url": "https://.../cdn/storage/attachments/.../original/spec.pdf",
    "urlDownload": "https://.../cdn/storage/attachments/.../download/spec.pdf",
    "boardId": "...",
    "swimlaneId": "...",
    "listId": "...",
    "cardId": "..."
  }
]
```

### `PUT /api/boards/:id/labels` — add a label

Body: `{ "label": { "name": "urgent", "color": "red" } }`. Label colors: `green`, `yellow`, `orange`, `red`, `purple`, `blue`, `sky`, `lime`, `pink`, `black`, `silver`, `peachpuff`, `crimson`, `plum`, `darkgreen`, `slateblue`, `magenta`, `gold`, `navy`, `gray`, `saddlebrown`, `paleturquoise`, `mistyrose`, `indigo`.

### `GET /api/boards/:id/cards_count`

Returns `{ "cards_count": <int> }`.

### `GET /public`

Public boards, no auth required.

### `GET /api/boards_count`

Total counts (admin).

### Email-domain sharing (admin)

- `GET /api/boards/:id/domains`
- `POST /api/boards/:id/domains` — body `{ "domain": "example.com" }`
- `DELETE /api/boards/:id/domains/:domain`

## Board members and roles

### `POST /api/boards/:id/members/:userId/add`

Adds a member to the board. **The `isAdmin: true` field in the body is ignored** on this endpoint — new members come in without admin. To promote them, immediately call the role-setting endpoint below.

### `POST /api/boards/:id/members/:userId/remove`

Removes a member. Removing a *deleted* user has silently no-op'd in older versions (issue #5330).

### `POST /api/boards/:id/members/:userId` — set role

Body:

```json
{
  "isAdmin": true,
  "isNoComments": false,
  "isCommentOnly": false,
  "isWorker": false
}
```

- `isAdmin` — full board admin.
- `isNoComments` — read-only.
- `isCommentOnly` — can comment but not edit cards.
- `isWorker` — limited role (assigned work only).

## Lists

Lists are the columns on a board.

### `GET /api/boards/:boardId/lists`

Array of `{ _id, title }`.

### `GET /api/boards/:boardId/lists/:listId`

Full list document.

### `POST /api/boards/:boardId/lists`

Body: `{ "title": "In progress" }`. Response: `{ "_id": "<newListId>" }`.

### `DELETE /api/boards/:boardId/lists/:listId`

## Swimlanes

Swimlanes are the horizontal rows. A board has at least one (the default swimlane, whose ID is returned when the board is created).

### `GET /api/boards/:boardId/swimlanes`
### `GET /api/boards/:boardId/swimlanes/:swimlaneId`
### `POST /api/boards/:boardId/swimlanes` — body `{ "title": "..." }`
### `PUT /api/boards/:boardId/swimlanes/:swimlaneId`
### `DELETE /api/boards/:boardId/swimlanes/:swimlaneId`
### `GET /api/boards/:boardId/swimlanes/:swimlaneId/cards`

## Cards

### `POST /api/boards/:boardId/lists/:listId/cards` — create a card

Body:

```json
{
  "title": "Investigate flaky test",
  "description": "Details...",
  "authorId": "<userId>",
  "swimlaneId": "<swimlaneId>",
  "members": ["<userId>"],
  "assignees": ["<userId>"]
}
```

`authorId` and `swimlaneId` are required. Response: `{ "_id": "<newCardId>" }`.

### `GET /api/boards/:boardId/cards/:cardId`

Full card document (many fields):

```
_id, title, description, listId, swimlaneId, boardId,
members, assignees, labelIds, receivedAt, startAt, dueAt, endAt,
spentTime, isOvertime, customFields, vote, poker, parentId (subtask), ...
```

### `PUT /api/boards/:boardId/lists/:fromListId/cards/:cardId` — update

Update any subset of fields. To **move a card between lists**, include `"listId": "<toListId>"` in the body. Note the `fromListId` in the URL is still the *current* list.

### `DELETE /api/boards/:boardId/lists/:listId/cards/:cardId`

### `GET /api/boards/:boardId/cards_count`
### `GET /api/boards/:boardId/lists/:listId/cards_count`

### `GET /api/boards/:boardId/cards/customField/:customFieldId?value=...`

Returns cards matching a custom-field value (exact name of the endpoint varies by version — check `models/cards.js`).

### `POST /api/boards/:boardId/cards/:cardId/customFields/:customFieldId` — set a custom field on a card

Body depends on field type: `{ "value": "..." }` for text/number; item id for dropdown.

## Checklists and checklist items

### `GET /api/boards/:boardId/cards/:cardId/checklists`
### `POST /api/boards/:boardId/cards/:cardId/checklists` — body `{ "title": "Acceptance criteria", "items": ["item 1","item 2"] }`
### `GET /api/boards/:boardId/cards/:cardId/checklists/:checklistId`
### `DELETE /api/boards/:boardId/cards/:cardId/checklists/:checklistId`

### `POST /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items` — body `{ "title": "..." }`
### `GET /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:itemId`
### `PUT /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:itemId` — body `{ "isFinished": true }` toggles the checkbox
### `DELETE /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:itemId`

## Card comments

### `GET /api/boards/:boardId/cards/:cardId/comments`
### `POST /api/boards/:boardId/cards/:cardId/comments` — body `{ "authorId": "<userId>", "comment": "..." }`
### `GET /api/boards/:boardId/cards/:cardId/comments/:commentId`
### `DELETE /api/boards/:boardId/cards/:cardId/comments/:commentId`

## Custom fields

### `GET /api/boards/:boardId/custom-fields`
### `POST /api/boards/:boardId/custom-fields`

Body:

```json
{
  "name": "Story points",
  "type": "number",
  "settings": {},
  "showOnCard": true,
  "automaticallyOnCard": false,
  "showLabelOnMiniCard": true,
  "showSumAtTopOfList": false,
  "authorId": "<userId>"
}
```

Valid `type`: `text`, `number`, `date`, `dropdown`, `checkbox`, `currency`, `stringtemplate`.

### `GET /api/boards/:boardId/custom-fields/:id`
### `PUT /api/boards/:boardId/custom-fields/:id`
### `DELETE /api/boards/:boardId/custom-fields/:id`

For `dropdown` fields, there are additional endpoints to add/edit/delete items — check `models/customFields.js`.

## Labels

Labels live on the board document (`board.labels`). Create/update via `PUT /api/boards/:id/labels` (see [Boards](#boards)). To apply to a card, add the label's `_id` to `card.labelIds` via a card update.

## Integrations (webhooks)

Outgoing webhooks configured per board.

### `GET /api/boards/:boardId/integrations`

**Note**: `GET` responses **strip the `token` field** for security. If you need the token, store it client-side when you create the integration.

### `POST /api/boards/:boardId/integrations`

```json
{
  "enabled": true,
  "title": "Slack notifier",
  "url": "https://hooks.example.com/wekan",
  "token": "<optional-shared-secret>",
  "activities": ["all"]
}
```

`activities` can be `["all"]` or a list of activity names (e.g. `"act-createCard"`, `"act-moveCard"`).

### `GET /api/boards/:boardId/integrations/:intId`
### `PUT /api/boards/:boardId/integrations/:intId`
### `DELETE /api/boards/:boardId/integrations/:intId`
### `.../integrations/:intId/activities` — GET the delivered activities log

See `references/webhook-data.md` for the payload shape and activity catalog.

## Attachments

Historically attachment upload over REST was missing (issue #1482). Current WeKan implements it via the routes wrapped by `api.py`. Exact paths vary by version — verify against `models/attachments.js`.

### `GET /api/boards/:boardId/attachments`

Returns the array shown earlier under [Boards](#boards).

### Upload

Typically `POST /api/boards/:boardId/swimlanes/:swimlaneId/lists/:listId/cards/:cardId/attachments` as `multipart/form-data` with a `file` field. `api.py`'s `uploadattachment` takes an optional storage-backend argument (`fs`, `gridfs`, `s3`).

### Download

`GET` the `urlDownload` returned by the attachments list. This is CDN storage, not the API root; it may require the same auth cookie/header.

### Delete

`DELETE /api/attachments/:attachmentId` (verify against `api.py`).

### Copy/move

`api.py` exposes `copymoveattachment` — POST with target board/swimlane/list/card IDs and `mode: "copy" | "move"`.

### Board background

Upload/download a board background image; see `api.py`'s `uploadbackground` / `downloadbackground`.

### Attachment settings (admin)

- `GET /api/admin/attachment-settings`
- `PUT /api/admin/attachment-settings` — body `{ "field": "<dotted.path>", "value": ... }`

Controls storage backend, max size, allowed MIME types, external AV scanning program.

## Admin and global settings

### `GET /api/settings` / `PUT /api/settings` — global admin

Field-whitelisted. SMTP credentials are never returned or writable through this endpoint.

## Error handling patterns

- **HTTP 401**: token expired, invalid, or `WITH_API` disabled. Re-login and retry.
- **HTTP 403**: token valid but the user lacks permission for the resource.
- **HTTP 404**: resource doesn't exist, or endpoint doesn't exist on this version. Verify the path in `models/*.js`.
- **HTTP 500**: server-side, often on LDAP/OIDC users hitting password login or on attachment bugs in older versions.
- **HTTP 200 with `{"error": ..., "reason": ...}` body**: business-logic error. Always parse the body before treating a 200 as success.
