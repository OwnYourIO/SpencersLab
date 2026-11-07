"""
WeKan MCP server.

Exposes typed tools over the WeKan REST API. Read/write scoped to the caller's
board membership, since the underlying WEKAN_TOKEN belongs to a specific user.

Design principles:
    - Credential lives in the process env (WEKAN_TOKEN). NEVER a tool parameter.
    - Each tool has a narrow, typed schema. No generic "wekan_call" passthrough
      (that would re-expose the whole admin surface to the model).
    - Tool responses are shaped down to the fields the model actually needs.
      Raw internal Mongo _id blobs, member arrays, and other clutter are stripped
      unless a tool's purpose is to return them.
    - Errors are sanitized. No Authorization header, no raw request, no traceback.
    - Entity-level destructive tools (delete_board, delete_card, delete_list,
      remove_member) are intentionally OMITTED. Three destructive ops ARE
      exposed — remove_rule, delete_checklist_item, and remove_card_dependency
      — each bounded to a single rule/item/card-edge and needed for board
      hygiene; their docstrings mark them as destructive. Add entity
      deletions back only if you want them, and mark with destructive hints.
    - WEKAN_MCP_READ_ONLY=true hides every write tool from the catalog
      (they are never registered), for the readonly server tier.

Transport: streamable-http on 0.0.0.0:8080 (chosen for Kubernetes;
    ToolHive proxies this to Claude Desktop / other clients).
"""

from __future__ import annotations

import logging
import os
import sys
import time
from typing import Optional

from fastmcp import FastMCP

from wekan_mcp.wekan import WekanClient, WekanError


# Logging goes to stderr only: stdout may be reserved for the stdio transport.
logging.basicConfig(
    stream=sys.stderr,
    level=os.environ.get("WEKAN_MCP_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("wekan-mcp")


# Set WEKAN_MCP_READ_ONLY=true on the readonly server tier: write tools are
# then never registered (hidden from tools/list, impossible to call). The
# admin tier leaves it unset and gets the full read+write surface.
READ_ONLY = os.environ.get("WEKAN_MCP_READ_ONLY", "").strip().lower() in (
    "1", "true", "yes", "on",
)


# The credential is validated ONCE at startup, never per tool call.
try:
    _wekan = WekanClient()
    _me = _wekan.validate()
    log.info("connected to WeKan as user_id=%s", _wekan.user_id)
except WekanError as e:
    # Fail fast and loud. ToolHive will restart the pod and surface this.
    log.error("startup failed: %s", e)
    raise SystemExit(1)

if READ_ONLY:
    log.info("READ-ONLY mode: write tools will NOT be registered")


mcp = FastMCP("wekan")

# In READ_ONLY mode write tools are defined but never registered: they vanish
# from the tool catalog and cannot be invoked at all.
_write_tool = (lambda fn: fn) if READ_ONLY else mcp.tool


def _slim_board(b: dict) -> dict:
    """Board with only what the model actually needs to reason about it."""
    return {
        "id": b.get("_id"),
        "title": b.get("title"),
        "key": b.get("key"),
        "permission": b.get("permission"),
        "color": b.get("color"),
        "archived": b.get("archived", False),
        "labels": [{"id": l.get("_id"), "name": l.get("name"), "color": l.get("color")}
                   for l in b.get("labels", []) if l],
    }


def _slim_card(c: dict) -> dict:
    return {
        "id": c.get("_id"),
        "title": c.get("title"),
        "description": c.get("description"),
        "board_id": c.get("boardId"),
        "list_id": c.get("listId"),
        "swimlane_id": c.get("swimlaneId"),
        "label_ids": c.get("labelIds", []),
        "member_ids": c.get("members", []),
        "assignee_ids": c.get("assignees", []),
        "due_at": c.get("dueAt"),
        "start_at": c.get("startAt"),
        "end_at": c.get("endAt"),
        "archived": c.get("archived", False),
        # cardNumber/customFields ride the /api/cards/:cardId full document;
        # the by-list projection strips them (see list_cards_in_list).
        "card_number": c.get("cardNumber"),
        "custom_fields": [
            {"id": cf.get("_id"), "value": cf.get("value")}
            for cf in c.get("customFields", []) if cf
        ],
        # Same rule for the cf-96 relations (server/models/cards.js): the
        # edges are stored on the source card as cardDependencies and the
        # lineage key is parentId — both present on the single-card document,
        # both stripped by the by-list projection, where they read as [] /
        # None rather than being invented here.
        "card_dependencies": c.get("cardDependencies", []),
        "parent_id": c.get("parentId"),
    }


def _slim_list(l: dict) -> dict:
    # swimlane_id is load-bearing: WeKan rules and card creation both need the
    # (list, swimlane) pair, and list titles repeat across swimlanes.
    return {"id": l.get("_id"), "title": l.get("title"), "swimlane_id": l.get("swimlaneId")}


def _slim_swimlane(s: dict) -> dict:
    return {"id": s.get("_id"), "title": s.get("title")}


def _slim_comment(c: dict) -> dict:
    return {
        "id": c.get("_id"),
        "comment": c.get("text") or c.get("comment"),
        "author_id": c.get("userId") or c.get("authorId"),
        "created_at": c.get("createdAt"),
    }


def _slim_rule(r: dict) -> dict:
    # WeKan's rules API already embeds the trigger and action inline with
    # internal fields (_id, boardId, timestamps) stripped server-side, so the
    # documents pass through as-is — they ARE the rule the model reasons about.
    # The cf-96 keys ride that same as-is posture, but they are load-bearing,
    # not cosmetic: the schema-2 snapshot capture contract reads a rule's
    # checklist extras and enabled flag through this projection, and without
    # them the get_rule capture path can never answer (RESEARCH F5).
    # serializeRule hydrates all three on the rule GET routes; the enabled
    # default guards legacy documents only — a paused rule must read
    # enabled: false, never a silent active.
    return {
        "id": r.get("_id"),
        "title": r.get("title"),
        "trigger": r.get("trigger"),
        "action": r.get("action"),
        "extra_actions": r.get("extraActions"),
        "extra_triggers": r.get("extraTriggers"),
        "enabled": r.get("enabled", True),
    }


# READ TOOLS

@mcp.tool
def list_boards() -> list[dict]:
    """List the boards the WeKan service user is a member of."""
    raw = _wekan.get(f"/api/users/{_wekan.user_id}/boards") or []
    # This endpoint returns {_id, title} pairs; fetch nothing else.
    return [{"id": b.get("_id"), "title": b.get("title")} for b in raw]


@mcp.tool
def get_board(board_id: str) -> dict:
    """Get a board's metadata: title, board key, permission, color, labels."""
    return _slim_board(_wekan.get(f"/api/boards/{board_id}") or {})


@mcp.tool
def list_lists(board_id: str) -> list[dict]:
    """List the lists (columns) on a board. Each entry carries its swimlane_id,
    so you can group lists by swimlane (list titles repeat across swimlanes)."""
    raw = _wekan.get(f"/api/boards/{board_id}/lists") or []
    out = []
    for l in raw:
        slim = _slim_list(l)
        # WeKan's collection endpoint hard-projects each list to {_id, title}
        # (verified in server/models/lists.js), so swimlaneId is absent there.
        # The single-list endpoint returns the full document — hydrate from it.
        if slim["id"] and slim["swimlane_id"] is None:
            try:
                full = _wekan.get(f"/api/boards/{board_id}/lists/{slim['id']}") or {}
                if isinstance(full, dict):
                    slim["swimlane_id"] = full.get("swimlaneId")
            except WekanError as e:
                # Degrade to null rather than failing the whole listing.
                log.warning("list_lists: could not hydrate list %s: %s", slim["id"], e)
        out.append(slim)
    return out


@mcp.tool
def list_swimlanes(board_id: str) -> list[dict]:
    """List the swimlanes (rows) on a board. Every board has at least one."""
    raw = _wekan.get(f"/api/boards/{board_id}/swimlanes") or []
    return [_slim_swimlane(s) for s in raw]


@mcp.tool
def list_cards_in_list(board_id: str, list_id: str) -> list[dict]:
    """List the cards in a specific list, in board order (leftmost/top first).

    WeKan's by-list endpoint returns a projection that omits cardNumber,
    customFields, labelIds, cardDependencies, parentId and listId, so here
    card_number comes back null, custom_fields/label_ids/card_dependencies
    are empty, parent_id is null; call get_card per candidate for the full
    card."""
    raw = _wekan.get(f"/api/boards/{board_id}/lists/{list_id}/cards") or []
    return [_slim_card(c) for c in raw]


@mcp.tool
def get_card(board_id: str, card_id: str) -> dict:
    """Get a single card with its main fields (title, description, dates, members)."""
    # WeKan has no /api/boards/:boardId/cards/:cardId route — the single-card
    # lookup is /api/cards/:cardId (it enforces board access server-side via
    # the card's own boardId; board_id is kept for interface consistency).
    # Note: this route also returns archived cards; check the "archived" field.
    return _slim_card(_wekan.get(f"/api/cards/{card_id}") or {})


@mcp.tool
def get_card_details(board_id: str, card_id: str) -> dict:
    """
    Everything a pipeline run needs from its claimed card in one read, in
    the shape the claim-time context block is written from: the card's own
    fields (incl. sort and parentId), its labels named from the board, its
    custom-field raw values named from the board's field list, EVERY
    checklist with its items in stored order, its dependency lines, and the
    slug field read both ways — slug_stack (the append-only history, oldest
    first) and current_slug (the newest entry, the one a run names its
    surfaces with).  A follow-up card's inherited Lifecycle answers are
    already its own checklist items, so no parent fetch is needed; archived
    cards come back with the archived flag set rather than being dropped.

    One MCP call, several REST reads: the card document carries no label or
    field names, and its checklists come as headers on the card-scoped
    collection route, so the names and the items are hydrated from the board
    document, the board's field list and the per-checklist route.  A card
    that cannot be read fails the call — an empty details payload would be
    indistinguishable from a card with nothing on it.  A checklist whose
    items cannot be read fails the call the same way: the run decides its
    Lifecycle stages from that item list, so an empty item list has to mean
    the checklist genuinely has no items.  Read only: writes nothing.
    """
    card = _wekan.get(f"/api/cards/{card_id}") or {}
    _embedded_error(card, "get_card_details")
    if not isinstance(card, dict) or not card:
        raise WekanError(
            f"get_card_details: card {card_id} did not read as a card document "
            f"(got {type(card).__name__}) — an empty payload here is not an empty card"
        )

    board = _wekan.get(f"/api/boards/{board_id}") or {}
    label_names = {
        l.get("_id"): l.get("name")
        for l in board.get("labels", []) if isinstance(l, dict)
    }
    fields = _wekan.get(f"/api/boards/{board_id}/custom-fields") or []
    field_names = {
        cf.get("_id"): cf.get("name")
        for cf in fields if isinstance(cf, dict)
    }
    # The slug field is found by NAME, like preload_board does: the board's
    # field id is not stable across boards, the vocabulary is.
    slug_field_ids = {fid for fid, name in field_names.items() if name == "slug"}

    custom_fields: dict = {}
    slug_stack: list = []
    current_slug: Optional[str] = None
    for entry in card.get("customFields") or []:
        if not isinstance(entry, dict):
            continue
        field_id = entry.get("_id")
        # A field the board no longer defines keeps its id as the key: an
        # orphaned value is surfaced, not dropped with its name.
        custom_fields[field_names.get(field_id) or field_id] = entry.get("value")
        if field_id in slug_field_ids:
            slug_stack = _slug_stack_from_combined_value(entry.get("value"))
            current_slug = _slug_from_combined_value(entry.get("value"))

    checklists: list = []
    for header in _wekan.get(
        f"/api/boards/{board_id}/cards/{card_id}/checklists"
    ) or []:
        if not isinstance(header, dict):
            continue
        cl_id = header.get("_id")
        # No fallback and no swallow here: items: [] is the shape of a checklist
        # that genuinely has no items, so a read that failed has to reach the
        # caller — its degrade arm can only fire on a call that actually failed.
        full = _wekan.get(
            f"/api/boards/{board_id}/cards/{card_id}/checklists/{cl_id}"
        )
        _embedded_error(full, "get_card_details")
        checklists.append({
            "id": cl_id,
            "title": header.get("title"),
            "items": [
                {"title": i.get("title"), "finished": bool(i.get("isFinished"))}
                for i in sorted(
                    (x for x in (full.get("items") or []) if isinstance(x, dict)),
                    key=_sort_key,
                )
            ],
        })

    return {
        "id": card.get("_id"),
        "card_number": card.get("cardNumber"),
        "title": card.get("title"),
        "description": card.get("description"),
        "list_id": card.get("listId"),
        "swimlane_id": card.get("swimlaneId"),
        "archived": bool(card.get("archived", False)),
        "sort": card.get("sort"),
        "parent_id": card.get("parentId"),
        "label_ids": card.get("labelIds", []),
        # id -> name: the card carries only ids and the block reads as a
        # lookup, so the names ride beside them rather than as a second list.
        "labels": {
            lid: label_names.get(lid)
            for lid in card.get("labelIds", []) if lid
        },
        # field name -> value exactly as stored: the run quotes the card's
        # own values, only the slug stack is additionally parsed.
        "custom_fields": custom_fields,
        "slug_stack": slug_stack,
        "current_slug": current_slug,
        "checklists": checklists,
        # Edges are stored on the source card (models/cards.js), so they ride
        # the card document already in hand.  cardId is the TARGET id; the
        # block never needs the icon, so it is not carried.
        "dependencies": [
            {
                "to_id": edge.get("cardId"),
                "type": edge.get("type"),
                "color": edge.get("color"),
            }
            for edge in (card.get("cardDependencies") or [])
            if isinstance(edge, dict)
        ],
    }


@mcp.tool
def list_comments(board_id: str, card_id: str) -> list[dict]:
    """List the comments on a card."""
    raw = _wekan.get(f"/api/boards/{board_id}/cards/{card_id}/comments") or []
    return [_slim_comment(c) for c in raw]


@mcp.tool
def list_checklists(board_id: str, card_id: str) -> list[dict]:
    """List the checklists on a card."""
    raw = _wekan.get(f"/api/boards/{board_id}/cards/{card_id}/checklists") or []
    return [{"id": c.get("_id"), "title": c.get("title")} for c in raw]


@mcp.tool
def get_checklist(board_id: str, card_id: str, checklist_id: str) -> dict:
    """Get a checklist with its items. Item ids are required by toggle_checklist_item."""
    raw = _wekan.get(
        f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}"
    ) or {}
    return {
        "id": raw.get("_id"),
        "title": raw.get("title"),
        "items": [
            {"id": i.get("_id"), "title": i.get("title"),
             "finished": i.get("isFinished", False)}
            for i in raw.get("items", []) if i
        ],
    }


@mcp.tool
def list_rules(board_id: str) -> list[dict]:
    """List the automation rules of a board. Each rule carries
    {id, title, trigger, action, extra_actions, extra_triggers, enabled} —
    trigger and action embed inline (e.g. trigger {activityType: moveCard,
    listName: Doing} + action {actionType: addMember, username: ...}), the
    checklist extras and the enabled flag pass through as the route returns
    them. Rule ids are required by get_rule, update_rule and remove_rule."""
    raw = _wekan.get(f"/api/boards/{board_id}/rules") or []
    return [_slim_rule(r) for r in raw]


@mcp.tool
def get_rule(board_id: str, rule_id: str) -> dict:
    """Get one automation rule with its full embedded trigger, action,
    checklist extras and enabled flag."""
    return _slim_rule(_wekan.get(f"/api/boards/{board_id}/rules/{rule_id}") or {})


@mcp.tool
def list_custom_fields(board_id: str) -> list[dict]:
    """List the custom fields defined on a board.

    WeKan's board-level list route returns only {_id, name, type} per row
    (v9.99); use get_custom_field for the full document (settings, dropdown
    items, placement flags)."""
    raw = _wekan.get(f"/api/boards/{board_id}/custom-fields") or []
    return [
        {"id": cf.get("_id"), "name": cf.get("name"), "type": cf.get("type")}
        for cf in raw if cf
    ]


@mcp.tool
def get_custom_field(board_id: str, custom_field_id: str) -> dict:
    """Get one board custom field with its settings and card-placement flags.

    type is one of text, number, date, dropdown, checkbox, currency,
    stringtemplate; dropdown options live in settings.dropdownItems.
    always_on_card is read-only through this server: REST create ignores
    the key and the existing-card backfill only runs when the WeKan UI
    form saves the flag — see create_custom_field."""
    raw = _wekan.get(
        f"/api/boards/{board_id}/custom-fields/{custom_field_id}"
    ) or {}
    return {
        "id": raw.get("_id"),
        "name": raw.get("name"),
        "type": raw.get("type"),
        "settings": raw.get("settings"),
        "show_on_card": raw.get("showOnCard"),
        "automatically_on_card": raw.get("automaticallyOnCard"),
        "always_on_card": raw.get("alwaysOnCard"),
    }


# WRITE TOOLS (skipped entirely when WEKAN_MCP_READ_ONLY is set)

# v9.99 createCard rules insert standard checklists asynchronously, AFTER the
# REST card-create response flushes (server/rulesHelper.js cascade), and the
# checklist document lands before its items are all in. So default_checked can
# neither assume nor one-shot the checklist: it awaits both phases with a
# bounded poll. Budget is sized for the observed ~1-2s cascade with headroom
# for slow boards, and stays finite so a misconfigured/deleted rule set
# surfaces as "missing" in the response instead of hanging the tool.
_DEFAULT_CHECKED_POLL_ATTEMPTS = 25
_DEFAULT_CHECKED_POLL_INTERVAL_S = 0.4


def _apply_default_checked(
    board_id: str,
    card_id: str,
    checklist_title: str,
    item_titles: list,
) -> dict:
    """
    Await one rules-created checklist (and the items inside it) on a card,
    then set the wanted item titles to checked. Returns
    {checked: [...applied or already-done titles...],
     missing: [...titles never found within the poll budget...],
     failed: [...found but rejected by the check PUT...]} — every wanted
    title lands in exactly one bucket, so a degraded run is visible in the
    response, never silent.

    Titles are matched byte-exactly: the rules' item lists and the caller's
    default_checked values are both maintained in this repo, and drift must
    report as missing rather than silently checking a near-match. Never
    creates checklists or items — creation belongs to the board rules;
    re-applying to an already-checked item is a no-op read, not a rewrite.
    """
    wanted = list(dict.fromkeys(item_titles))
    wanted_set = set(wanted)
    if not wanted:
        return {"checked": [], "missing": [], "failed": []}
    checklist_id = None
    # title -> (item_id, already_finished); the list route projects checklists
    # to {_id, title} only (server/models/checklists.js GET), so item titles
    # come from the single-checklist route, which embeds items inline.
    found: dict = {}
    for attempt in range(_DEFAULT_CHECKED_POLL_ATTEMPTS):
        try:
            if checklist_id is None:
                for cl in _wekan.get(
                    f"/api/boards/{board_id}/cards/{card_id}/checklists"
                ) or []:
                    if cl.get("title") == checklist_title:
                        checklist_id = cl.get("_id")
                        break
            if checklist_id and len(found) < len(wanted_set):
                doc = _wekan.get(
                    f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}"
                ) or {}
                for item in doc.get("items", []):
                    title = item.get("title")
                    if title in wanted_set and title not in found and item.get("_id"):
                        found[title] = (item.get("_id"), bool(item.get("isFinished")))
        except WekanError as e:
            # A read failing mid-cascade (card visibility timing, transient
            # 404/500 — sendJsonResult maps codes to HTTP status) counts as
            # "not yet", not as fatal: the budget ends the poll, not errors.
            log.debug("default_checked: poll attempt %d for %r: %s", attempt, checklist_title, e)
        if checklist_id and len(found) >= len(wanted_set):
            break
        if attempt + 1 < _DEFAULT_CHECKED_POLL_ATTEMPTS:
            time.sleep(_DEFAULT_CHECKED_POLL_INTERVAL_S)

    checked: list = []
    failed: list = []
    for title in wanted:
        if title not in found:
            continue
        item_id, already_finished = found[title]
        if already_finished:
            checked.append(title)
            continue
        try:
            # v9.99 server/models/checklistItems.js PUT /api/boards/:boardId/
            # cards/:cardId/checklists/:checklistId/items/:itemId (L163-215)
            # accepts the isFinished key (L195-200) and writes through
            # ChecklistItems.direct.updateAsync — hook-bypass: no activity,
            # no rule re-trigger, idempotent, safe for repeat create_card.
            _wekan.put(
                f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items/{item_id}",
                json_body={"isFinished": True},
            )
            checked.append(title)
        except WekanError as e:
            log.warning(
                "default_checked: could not check %r in checklist %r on card %s: %s",
                title, checklist_title, card_id, e,
            )
            failed.append(title)

    return {
        "checked": checked,
        "missing": [t for t in wanted if t not in found],
        "failed": failed,
    }


def _validate_default_checked(default_checked: dict) -> None:
    """
    Reject a malformed default_checked before any card exists: a shape mistake
    must surface as a clean tool error, not as a post-create surprise or a
    silent per-character walk — the "never an exception after the card
    exists" contract. Accepted shape is the documented one: a dict of
    {checklist title: [item title, ...]}; an empty item list is a no-op,
    not an error.
    """
    if not isinstance(default_checked, dict):
        raise WekanError(
            f"default_checked must be a dict mapping checklist title to a list "
            f"of item titles, got {type(default_checked).__name__}"
        )
    for checklist_title, titles in default_checked.items():
        if not isinstance(titles, list):
            raise WekanError(
                f"default_checked[{checklist_title!r}] must be a list of item "
                f"titles, got {type(titles).__name__}"
            )
        for t in titles:
            if not isinstance(t, str):
                raise WekanError(
                    f"default_checked[{checklist_title!r}] item titles must be "
                    f"strings, got {type(t).__name__}"
                )


@_write_tool
def create_card(
    board_id: str,
    list_id: str,
    swimlane_id: str,
    title: str,
    description: str = "",
    default_checked: Optional[dict] = None,
    parent_id: Optional[str] = None,
) -> dict:
    """
    Create a card in a specific list and swimlane. The service user is used
    as the card author. Returns the new card's id and title.

    default_checked optionally maps a checklist TITLE to the list of item
    titles that must arrive CHECKED on the new card, e.g. {"Model(s)":
    ["Qwen Flash", "Local (gpu-ai)"]}. A malformed map (not title -> list of
    strings) is rejected BEFORE the card is created. The board's createCard
    rules create the standard checklists asynchronously after the card-create
    response, so the tool bounded-polls (~10s) for each checklist and its
    items, then PUTs isFinished on the exact-title matches — the checked
    state is set without relying on rule dispatch order, which is
    unspecified. Item titles already checked are left as-is; nothing is
    created here (the rules own creation). The response gains
    "default_checked": {<title>: {checked, missing, failed}}; the card is
    NOT rolled back on any default failure, so callers must read
    "missing"/"failed" instead of assuming.

    parent_id optionally records creation lineage (a follow-up card made
    from another): the card is created first, then its parentId is set with
    a PUT on the single-card route — two steps because the single-card POST
    route ignores a body parentId while the PUT reads it (v12.65
    server/models/cards.js). A failed lineage step reports
    "parent_id_set": false + "parent_id_error" and never rolls the card
    back (the default_checked posture); absent parent_id leaves the create
    exactly as before. Lineage is parentId-only: this tool never writes a
    typed card edge as a side effect of setting the parent.
    """
    if default_checked:
        _validate_default_checked(default_checked)
    body = {
        "title": title,
        "description": description,
        "authorId": _wekan.user_id,
        "swimlaneId": swimlane_id,
    }
    resp = _wekan.post(f"/api/boards/{board_id}/lists/{list_id}/cards", json_body=body) or {}
    card_id = resp.get("_id")
    out: dict = {"id": card_id, "title": title}
    if default_checked:
        if not card_id:
            raise WekanError(
                f"card create returned no id for {title!r}; cannot apply default_checked"
            )
        out["default_checked"] = {
            checklist_title: _apply_default_checked(
                board_id, card_id, checklist_title, titles or []
            )
            for checklist_title, titles in default_checked.items()
        }
    if parent_id:
        out["parent_id"] = parent_id
        if not card_id:
            # Same surfacing rule as a default_checked failure: report the
            # miss, never raise over a card that may exist.
            out["parent_id_set"] = False
            out["parent_id_error"] = "card create returned no id; nothing to PUT"
        else:
            try:
                _wekan.put(
                    f"/api/boards/{board_id}/cards/{card_id}",
                    json_body={"parentId": parent_id},
                )
                out["parent_id_set"] = True
            except WekanError as e:
                out["parent_id_set"] = False
                out["parent_id_error"] = str(e)
    return out


@_write_tool
def update_card(
    board_id: str,
    list_id: str,
    card_id: str,
    title: Optional[str] = None,
    description: Optional[str] = None,
    due_at: Optional[str] = None,
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
) -> dict:
    """
    Update mutable fields on a card. Any argument left as None is not changed.
    Dates are ISO 8601 strings (e.g. '2026-08-15T17:00:00Z').
    """
    body: dict = {}
    if title is not None: body["title"] = title
    if description is not None: body["description"] = description
    if due_at is not None: body["dueAt"] = due_at
    if start_at is not None: body["startAt"] = start_at
    if end_at is not None: body["endAt"] = end_at
    if not body:
        return {"updated": False, "reason": "no fields provided"}
    _wekan.put(f"/api/boards/{board_id}/lists/{list_id}/cards/{card_id}", json_body=body)
    return {"updated": True, "card_id": card_id, "fields": list(body.keys())}


@_write_tool
def move_card(
    board_id: str,
    from_list_id: str,
    card_id: str,
    to_list_id: str,
    to_swimlane_id: Optional[str] = None,
) -> dict:
    """
    Move a card between lists (and optionally between swimlanes). The
    from_list_id is where the card currently lives; to_list_id is the destination.
    """
    body: dict = {"listId": to_list_id}
    if to_swimlane_id:
        body["swimlaneId"] = to_swimlane_id
    _wekan.put(f"/api/boards/{board_id}/lists/{from_list_id}/cards/{card_id}", json_body=body)
    return {"moved": True, "card_id": card_id, "to_list_id": to_list_id}


@_write_tool
def create_list(
    board_id: str,
    title: str,
    swimlane_id: Optional[str] = None,
    position: Optional[int] = None,
) -> dict:
    """
    Create a list (column) on a board, optionally bound to a swimlane and
    optionally repositioned after creation. The response is hydrated from a
    single-list read-back so a caller that omitted swimlane_id learns which
    swimlane WeKan actually bound.

    v12.64 facts (server/models/lists.js, source-checked 2026-10-29): the
    create route APPENDS — it sets sort from the board-wide live-list count,
    so on a multi-swimlane board the new column is not necessarily last
    inside the chosen swimlane. The route binds swimlaneId from the body or
    falls back to the board's default (first) swimlane, so the key is sent
    only when swimlane_id is given — omitting it must not arrive as an empty
    value, which would defeat that fallback. position is 0-based from the
    left, among the board's live lists, and rides a second, same-board move
    POST (the only REST-driven placement control for a new list); it is not
    atomic with the create. A failed reposition leaves the list live at the
    board end and reports positioned=false + position_error — it never
    fails the create and nothing rolls back (precedent: create_card's
    default_checked outcome buckets). A failed read-back nulls the echoed
    swimlane_id and sort instead of surfacing a succeeded create as an
    error (precedent: list_lists' hydrate warning).
    """
    body: dict = {"title": title}
    if swimlane_id:
        body["swimlaneId"] = swimlane_id
    resp = _wekan.post(f"/api/boards/{board_id}/lists", json_body=body) or {}
    list_id = resp.get("_id")

    positioned = True
    position_error: Optional[str] = None
    if position is not None:
        move_body: dict = {"position": position}
        if swimlane_id:
            move_body["toSwimlaneId"] = swimlane_id
        try:
            _wekan.post(
                f"/api/boards/{board_id}/lists/{list_id}/move", json_body=move_body
            )
        except WekanError as e:
            # The create already landed: report the placement miss, never
            # raise it into a failed create (no rollback by design).
            positioned = False
            position_error = str(e)
            log.warning("create_list: reposition of list %s failed: %s", list_id, e)

    swimlane_bound = None
    sort = None
    if list_id:
        try:
            full = _wekan.get(f"/api/boards/{board_id}/lists/{list_id}") or {}
        except WekanError as e:
            # Degrade the echoed fields to null: the list exists, so a
            # read-back miss must not surface as a create error.
            full = {}
            log.warning("create_list: could not hydrate list %s: %s", list_id, e)
        if isinstance(full, dict):
            swimlane_bound = full.get("swimlaneId")
            sort = full.get("sort")

    return {
        "id": list_id,
        "title": title,
        "swimlane_id": swimlane_bound,
        "sort": sort,
        "positioned": positioned,
        "position_error": position_error,
    }


@_write_tool
def add_comment(board_id: str, card_id: str, comment: str) -> dict:
    """Add a comment on a card, authored by the service user."""
    body = {"authorId": _wekan.user_id, "comment": comment}
    resp = _wekan.post(f"/api/boards/{board_id}/cards/{card_id}/comments", json_body=body) or {}
    return {"id": resp.get("_id"), "comment": comment}


@_write_tool
def add_checklist(
    board_id: str,
    card_id: str,
    title: str,
    items: Optional[list[str]] = None,
) -> dict:
    """Add a checklist to a card, optionally with an initial set of items."""
    body: dict = {"title": title}
    if items:
        body["items"] = items
    resp = _wekan.post(f"/api/boards/{board_id}/cards/{card_id}/checklists", json_body=body) or {}
    return {"id": resp.get("_id"), "title": title, "items_added": len(items or [])}


@_write_tool
def toggle_checklist_item(
    board_id: str,
    card_id: str,
    checklist_id: str,
    item_id: str,
    done: bool,
) -> dict:
    """Mark a checklist item done (True) or undone (False)."""
    _wekan.put(
        f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items/{item_id}",
        json_body={"isFinished": done},
    )
    return {"item_id": item_id, "done": done}


@_write_tool
def add_checklist_item(
    board_id: str,
    card_id: str,
    checklist_id: str,
    title: str,
) -> dict:
    """
    Append one item to a card's existing checklist — for extending the
    standard option sets on cards created before the option existed (rules
    only cover future cards). The item starts unchecked; use
    toggle_checklist_item to check it. Checklist ids come from
    list_checklists. WeKan answers 404 when the checklist does not belong
    to that card.
    """
    resp = _wekan.post(
        f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items",
        json_body={"title": title},
    ) or {}
    return {"id": resp.get("_id"), "checklist_id": checklist_id, "title": title}


@_write_tool
def delete_checklist_item(
    board_id: str,
    card_id: str,
    checklist_id: str,
    item_id: str,
) -> dict:
    """
    DESTRUCTIVE: permanently remove one checklist item from a card's
    checklist — for pruning abandoned options after a plan is settled.
    There is no undo; to keep the item but change its state use
    toggle_checklist_item. Item ids come from get_checklist; WeKan rejects
    the delete (404) when the item does not belong to that card/checklist.
    """
    _wekan.delete(
        f"/api/boards/{board_id}/cards/{card_id}/checklists/{checklist_id}/items/{item_id}"
    )
    return {"deleted": True, "item_id": item_id}


@_write_tool
def create_rule(board_id: str, title: str, trigger: dict, action: dict) -> dict:
    """
    Create an automation rule on a board: when TRIGGER fires, perform ACTION.

    trigger must include "activityType" (e.g. "createCard", "moveCard",
    "editCard"; also "scheduledTrigger" with scheduleKind/days/atTime, or
    "button"). Matching fields you omit (listName, oldListName, swimlaneName,
    cardTitle, userId) default to the '*' wildcard, so the rule fires for any
    value. action must include "actionType" (e.g. "addMember", "removeMember",
    "moveCardToTop", "archive").
    Example: trigger {"activityType": "moveCard", "listName": "Doing"} +
    action {"actionType": "addMember", "username": "someuser"}.
    Text fields of some actions support {variable} substitution, expanded at
    rule time — sendEmail's emailTo/emailSubject/emailMsg, and created
    card/checklist/swimlane names. Variables: {cardname}/{cardtitle},
    {cardnumber}, {description}, {duedate}, {listname}, {swimlanename},
    {boardname}, {username}, {date}, {time}, {datetime}.
    Returns the new rule's id and title.
    """
    body = {"title": title, "trigger": trigger, "action": action}
    resp = _wekan.post(f"/api/boards/{board_id}/rules", json_body=body) or {}
    return {"id": resp.get("_id"), "title": title}


@_write_tool
def update_rule(
    board_id: str,
    rule_id: str,
    title: Optional[str] = None,
    trigger: Optional[dict] = None,
    action: Optional[dict] = None,
) -> dict:
    """
    Edit an automation rule. Any argument left as None is not changed. A
    supplied trigger or action REPLACES the stored one wholesale, so include
    every field the rule should keep matching on.
    """
    body: dict = {}
    if title is not None: body["title"] = title
    if trigger is not None: body["trigger"] = trigger
    if action is not None: body["action"] = action
    if not body:
        return {"updated": False, "reason": "no fields provided"}
    _wekan.put(f"/api/boards/{board_id}/rules/{rule_id}", json_body=body)
    return {"updated": True, "rule_id": rule_id, "fields": list(body.keys())}


@_write_tool
def remove_rule(board_id: str, rule_id: str) -> dict:
    """
    DESTRUCTIVE: remove an automation rule, including its trigger and action.
    There is no undo — a removed rule must be recreated via create_rule. Only
    use for rules the user explicitly asked to delete.
    """
    _wekan.delete(f"/api/boards/{board_id}/rules/{rule_id}")
    return {"removed": True, "rule_id": rule_id}


@_write_tool
def create_custom_field(
    board_id: str,
    name: str,
    type: str,
    settings: Optional[dict] = None,
    show_on_card: bool = True,
    automatically_on_card: bool = False,
    show_label_on_minicard: bool = False,
    show_sum_at_top_of_list: bool = False,
) -> dict:
    """
    Create a board-level custom field. type is one of text, number, date,
    dropdown, checkbox, currency, stringtemplate (v9.99 schema). settings
    must be a JSON object — send {"dropdownItems": [...]} for dropdowns and
    {} (the default) otherwise; WeKan's REST create stores it verbatim, so
    never send the json.dumps string form api.py uses for urlencoded calls.

    WARNING (v9.99): REST create IGNORES alwaysOnCard — the handler reads
    only name/type/settings/showOnCard/automaticallyOnCard/
    showLabelOnMiniCard/showSumAtTopOfList — and it inserts through the
    unhooked direct path, so existing cards are NOT backfilled with the new
    field (no addToAllCards run). Cards created over REST after this call
    carry the field when automatically_on_card is set; for existing cards,
    set_card_custom_field attaches the field as a side effect of setting
    the value. Returns the new field's id.
    """
    body = {
        "name": name,
        "type": type,
        "settings": settings or {},
        "showOnCard": show_on_card,
        "automaticallyOnCard": automatically_on_card,
        "showLabelOnMiniCard": show_label_on_minicard,
        "showSumAtTopOfList": show_sum_at_top_of_list,
        # WeKan attributes the createCustomField activity to
        # req.body.authorId; without it the audit record is ownerless.
        "authorId": _wekan.user_id,
    }
    resp = _wekan.post(f"/api/boards/{board_id}/custom-fields", json_body=body) or {}
    return {"id": resp.get("_id")}


@_write_tool
def set_card_custom_field(
    board_id: str,
    card_id: str,
    custom_field_id: str,
    value: str,
) -> dict:
    """
    Set a custom-field value on a card (upsert: attach the field first when
    the card does not carry it yet). Reads the card to learn its current
    list and attached fields, then: field already attached → POST the
    dedicated value route; not attached → PUT the whole customFields array
    with the entry appended, because WeKan's value route maps over the
    card's existing array and silently no-ops on unattached fields (v9.99).
    Returns {card_id, custom_field_id, value, attached}, attached=True
    meaning the field was already on the card (value-only update leg).

    The attach leg is a whole-array read-modify-write and can race
    concurrent UI edits (an entry written between the read and the PUT is
    lost). Accepted on the single-agent boards this server targets; on
    busy boards attach the field via the UI first. Both legs exclude
    archived cards (v9.99 selectors filter archived:false): the update
    leg errors, the attach leg silently updates nothing.

    value is stored verbatim on the card entry (no type coercion on these
    paths): text/date fields take strings, dropdown fields take a
    dropdown-item id. number/checkbox fields want JSON numbers/booleans
    this typed schema cannot express — use raw REST for those.
    """
    card = _wekan.get(f"/api/cards/{card_id}") or {}
    list_id = card.get("listId")
    if not list_id:
        raise WekanError(f"Card {card_id} not found or has no listId")
    existing = [cf for cf in (card.get("customFields") or []) if cf]
    attached = any(cf.get("_id") == custom_field_id for cf in existing)
    if attached:
        _wekan.post(
            f"/api/boards/{board_id}/lists/{list_id}/cards/{card_id}/customFields/{custom_field_id}",
            json_body={"value": value},
        )
    else:
        existing.append({"_id": custom_field_id, "value": value})
        _wekan.put(
            f"/api/boards/{board_id}/lists/{list_id}/cards/{card_id}",
            json_body={"customFields": existing},
        )
    return {
        "card_id": card_id,
        "custom_field_id": custom_field_id,
        "value": value,
        "attached": attached,
    }


# v102 BOARD PROVISIONING (cf-89) — deliberately ONE additive block spanning
# both kinds, not split across the READ/WRITE sections above: the sibling
# contract tests/wekan-mcp/create-list.sh pins server.py to a single additive
# hunk against the pre-ticket base (one reviewable block). Route facts are
# grounded on upstream v12.65 (RESEARCH.md, source-checked 2026-10-30);
# v9.88 is the documented low bound the 200-guards below defend.

# The 25 label colors of WeKan's config/const.js (LABEL_COLORS = ALLOWED_
# COLORS), byte-identical from v9.88 through v12.65 (RESEARCH.md §3). This
# list is a version pin: a WeKan upgrade that moves the palette drifts the
# client-side gate against the server's own 400, so re-verify on upgrade.
_LABEL_COLORS = (
    "white", "green", "yellow", "orange", "red", "purple", "blue", "sky",
    "lime", "pink", "black", "silver", "peachpuff", "crimson", "plum",
    "darkgreen", "slateblue", "magenta", "gold", "navy", "gray",
    "saddlebrown", "paleturquoise", "mistyrose", "indigo",
)


def _embedded_error(resp, what: str) -> None:
    """
    Reject an error body that arrived with HTTP 200. At the v9.88 low bound
    WeKan's catch sends the serialized Meteor.Error body at status 200, and
    WekanClient raises only when the dict carries BOTH `error` and `reason`
    — the single-key {"error": msg} fallback would otherwise read as a
    success (RESEARCH.md §5). The live v12.65 server answers real 4xx, so
    this guards the documented bound, not the common path. Safe per tool:
    every caller owns its expected shape (title echo, {_id}, bare label-id
    string, board document), and none of those can carry a top-level
    `error` key legitimately.
    """
    if isinstance(resp, dict) and "error" in resp:
        reason = f" ({resp['reason']})" if "reason" in resp else ""
        raise WekanError(
            f"{what}: WeKan answered 200 with an error body: {resp['error']}{reason}"
        )


@mcp.tool
def list_board_members(board_id: str) -> dict:
    """
    List a board's members: user ids plus nine normalized role booleans —
    isAdmin and isActive (schema-required) and the seven optional role
    flags; present reads as true, absent as false. Board ownership is the
    entry with is_admin=true (there is no owner field); grantedBy
    provenance is omitted.

    No username is resolved and none is fetched: usernames ride only the
    site-admin-gated GET /api/users routes and the service user is not
    site admin, so each entry carries username: null plus the
    username_resolution note saying why — silent nulls are the documented
    anti-pattern.

    v12.65 route facts (source-checked 2026-10-30): GET /api/boards/:id is
    gated checkBoardAccess — 403 when the service user is not a member,
    404 when the board does not exist. At the 9.88 low bound both arrive
    as 200 + embedded error body; the guard below catches that shape.
    """
    doc = _wekan.get(f"/api/boards/{board_id}") or {}
    _embedded_error(doc, "list_board_members")
    if not isinstance(doc, dict) or "_id" not in doc or not isinstance(doc.get("members"), list):
        raise WekanError(
            f"list_board_members: board document for {board_id} lacks _id "
            f"and/or a members list; got {doc!r}"
        )
    members = []
    for m in doc.get("members", []):
        if not isinstance(m, dict):
            continue
        entry = {"user_id": m.get("userId"), "username": None}
        for wire, snake in (
            ("isAdmin", "is_admin"),
            ("isActive", "is_active"),
            ("isNoComments", "is_no_comments"),
            ("isCommentOnly", "is_comment_only"),
            ("isWorker", "is_worker"),
            ("isNormalAssignedOnly", "is_normal_assigned_only"),
            ("isCommentAssignedOnly", "is_comment_assigned_only"),
            ("isReadOnly", "is_read_only"),
            ("isReadAssignedOnly", "is_read_assigned_only"),
        ):
            entry[snake] = bool(m.get(wire))
        members.append(entry)
    return {
        "board_id": doc.get("_id"),
        "title": doc.get("title"),
        "members": members,
        "username_resolution": (
            "WeKan publishes usernames only on site-admin-gated routes "
            "(GET /api/users[/:userId]); the service user is not site admin "
            "— resolve names out-of-band"
        ),
    }


@_write_tool
def update_board(board_id: str, title: str) -> dict:
    """
    Rename a board — title only. The sanctioned REST rename is the
    dedicated title route (a $set of the title field, hook-bypass: no
    activity, no rules); a bare PUT of the whole board document is 405
    upstream (#5299), so never rebuild one out of POST+DELETE — that
    would mint a new board id and reset the board. The cardNumber
    sequence is not on the board document at all (per-board counter
    cardNumber-<boardId> in the Counters collection), so a rename
    preserves the board id, every child id, and the whole
    cf-<cardNumber> slug sequence by construction.

    v12.65 route facts (source-checked 2026-10-30): the gate is
    checkBoardAdmin — a plain write member gets 403 and the title stays
    unchanged; 404 means the board does not exist or is not visible to
    the service user. No REST route changes board color or permission,
    and board key (2-10 capitals, auto-assigned on insert, REST-
    immutable) cannot be changed here — the echo only carries it.

    The echo is hydrated from a GET of the board document; a failed
    read-back nulls the echoed fields and logs a warning — the rename
    already succeeded and nothing rolls back (precedent: create_list).
    """
    resp = _wekan.put(f"/api/boards/{board_id}/title", json_body={"title": title})
    _embedded_error(resp, "update_board")
    if not isinstance(resp, dict) or resp.get("_id") != board_id:
        raise WekanError(
            f"update_board: title PUT for board {board_id} answered without a "
            f"matching _id; rename unconfirmed: {resp!r}"
        )
    board: dict = {}
    try:
        board = _wekan.get(f"/api/boards/{board_id}") or {}
    except WekanError as e:
        log.warning(
            "update_board: rename of board %s succeeded but read-back failed: %s",
            board_id, e,
        )
    if isinstance(board, dict) and board.get("_id") == board_id:
        return {
            "id": board_id,
            "title": board.get("title"),
            "key": board.get("key"),
            "color": board.get("color"),
            "permission": board.get("permission"),
            "archived": board.get("archived", False),
            "renamed": True,
        }
    return {
        "id": board_id,
        "title": None,
        "key": None,
        "color": None,
        "permission": None,
        "archived": None,
        "renamed": True,
    }


@_write_tool
def create_swimlane(board_id: str, title: str, sort: Optional[int] = None) -> dict:
    """
    Create a swimlane (row) on a board. sort is an explicit position the
    server honors since upstream #3624; omitted sort appends at
    max(live sibling sort)+1. The key is sent only when sort is not None
    — a bare-truthy gate would silently drop the legal sort=0. The
    response {id, title, sort} is hydrated from the single-swimlane GET:
    the create POST answers only {_id}, and the collection GET projects
    sort away (read-back precedent: create_list). A failed read-back
    nulls the echoed sort — the swimlane was still created.

    v12.65 route facts (source-checked 2026-10-30): gate is
    checkBoardWriteAccess — 403 when the service user lacks board write
    access, 404 when the board does not exist. At the 9.88 low bound an
    auth or schema failure can arrive as 200 + a serialized error body,
    so a response without _id is a failure regardless of status code.
    """
    body: dict = {"title": title}
    if sort is not None:
        body["sort"] = sort
    resp = _wekan.post(f"/api/boards/{board_id}/swimlanes", json_body=body)
    _embedded_error(resp, "create_swimlane")
    swimlane_id = resp.get("_id") if isinstance(resp, dict) else None
    if not swimlane_id:
        raise WekanError(
            f"create_swimlane: swimlane create for {title!r} returned no id "
            f"(rejected or not created): {resp!r}"
        )
    sort_out = None
    try:
        full = _wekan.get(f"/api/boards/{board_id}/swimlanes/{swimlane_id}") or {}
    except WekanError as e:
        full = {}
        log.warning("create_swimlane: could not hydrate swimlane %s: %s", swimlane_id, e)
    if isinstance(full, dict):
        sort_out = full.get("sort")
    return {"id": swimlane_id, "title": title, "sort": sort_out}


@_write_tool
def create_label(board_id: str, name: str, color: str = "green") -> dict:
    """
    Create a board label, or reuse the existing one: (name, color) is the
    idempotency key, so re-creating an existing pair returns the existing
    label id, while the same name with a different color creates a
    second label — there is no rename-by-name here.

    color must be one of the 25 named colors of WeKan's config/const.js
    (white included); an unknown or hex value is rejected client-side,
    naming the allowed list, before any request — the server's own 400
    (Invalid label color ...) stays the authority. The documented
    {"label": {name, color}} body form is the only one exposed; the
    string-form passthrough exists server-side but is not surfaced
    through this typed schema. tool-side color defaults to green, which
    is also the server's default.

    v12.65 route facts (source-checked 2026-10-30): the label route is
    gated inline board-admin-or-site-admin and answers clean 401/403/404
    (404 board not found, 403 not an admin); the handler returns the
    label id as a BARE JSON string — the new id, or the existing one for
    an idempotent repeat.
    """
    if color not in _LABEL_COLORS:
        raise WekanError(
            f"create_label: unknown color {color!r}. Allowed colors: "
            f"{', '.join(_LABEL_COLORS)} — WeKan stores named colors only, "
            f"hex values are never valid."
        )
    resp = _wekan.put(
        f"/api/boards/{board_id}/labels",
        json_body={"label": {"name": name, "color": color}},
    )
    if isinstance(resp, str):
        if not resp:
            raise WekanError(
                f"create_label: label PUT for {name!r} answered an empty "
                f"string, not a label id"
            )
        return {"label_id": resp, "name": name, "color": color}
    _embedded_error(resp, "create_label")
    raise WekanError(
        f"create_label: unexpected non-string response for label {name!r} on "
        f"board {board_id}: {resp!r}"
    )


# cf-96 CARD DEPENDENCIES, BOARD PRELOAD, BULK LABELS — deliberately ONE
# additive block (the cf-89 v102 precedent: the deploy diff stays reviewable as
# a single hunk). Route facts are grounded on upstream v12.65 reads (ticket
# RESEARCH.md §1.3/§2 and sources S1/S4/S9/S11, source-checked 2026-11-01); no
# route in this block was agent-probed live (pipeline sessions hold no bearer),
# so the doc evidence stamps stay source-only until the C10 runbook's user
# probe upgrades them. The v9.88 low bound is defended the same way as the
# v102 block: _embedded_error on 200-shaped error bodies.

# The seven dependency types of upstream models/metadata/dependencies.js.
# This tuple is a version pin (same posture as _LABEL_COLORS): a WeKan upgrade
# that moves the list drifts the client-side gate against the server's own
# 400, so re-verify on upgrade.
_DEPENDENCY_TYPES = (
    "related-to", "blocks", "is-blocked-by", "fixes", "is-fixed-by",
    "duplicates", "is-duplicated-by",
)

# The bulk-label route's own bound (server/models/cards.js, v12.65): one call
# addresses at most 500 cards. Gated client-side so an over-cap batch fails
# with the cap named instead of a bare 4xx from the server.
_BULK_LABEL_CARD_CAP = 500

# The kickoff vocabulary the preload keeps (boards skill's card-driven kickoff:
# the five standard checklists, plus `Research` — the legacy stand-in for
# Lifecycle on pre-cutover cards). Titles are the only stable key: checklist
# ids are per-card and per-board, so filtering is by title.
_PRELOAD_CHECKLIST_TITLES = {
    "Services", "Type", "Model(s)", "Lifecycle", "Human in the Loop", "Research",
}

# A checklist carrying exactly this many items is read as the legacy Lifecycle
# spelling: the retired generation predates the current stage names, so its
# title is not in the set above and its item count is the only handle the
# export gives. The trade-off is deliberate — a false positive costs payload
# bytes, a miss costs the consumer a per-card checklist fan-out.
_PRELOAD_LEGACY_LIFECYCLE_ITEMS = 8

_LAST_SORT = float("inf")


def _sort_key(item: dict) -> tuple:
    """
    Board walk order for preload reshaping: numeric sort first, a row without
    a sort value last (None never compares against numbers, and an export row
    missing sort is surfaced, not crashed on).
    """
    s = item.get("sort")
    return (s is None, _LAST_SORT if s is None else s)


def _slug_stack_from_combined_value(value: Optional[str]) -> list[str]:
    """
    Every [<slug>](<session link>) line of a combined slug-field value,
    oldest first — the whole append-only history, and the only walk of that
    line shape in this module: `_slug_from_combined_value` reduces its last
    entry, so the current slug can never disagree with the stack it came from.
    A value with no bracket pair at all — a bare legacy slug, prose — is a
    one-entry stack of that value rather than an empty one: pre-flip cards
    carry a bare slug, and every card must satisfy
    `current_slug == slug_stack[-1]`.  A line with no bracket pair inside a
    bracketed stack (a trailing prose note) is not an entry; a missing or
    empty value is an empty stack, which is "this card carries no stack", not
    a failed read.
    """
    if value is None or value == "":
        return []
    entries: list[str] = []
    for raw in value.splitlines():
        line = raw.strip()
        link = line.index("](") if "](" in line else -1
        # The bracket pair has to sit inside the line: index 0 would mean the
        # line opens with the link, i.e. there is no bracketed text.
        if link > 0 and line[0] == "[" and line.endswith(")"):
            entries.append(line[1:link])
    if entries:
        return entries
    bare = value.strip()
    return [bare] if bare else []


def _slug_from_combined_value(value: Optional[str]) -> Optional[str]:
    """
    The newest entry of a combined slug-field value — the single authority the
    boards skill points at for the [<slug>](<session link>) format, and the
    card's current slug. The field is an append-only STACK and the newest run
    appends the LAST line, so the newest entry is the stack parser's last one;
    a bare legacy slug or prose value is that one-entry stack, so it reads
    back as the value itself. None and the empty string both read as unset.
    """
    stack = _slug_stack_from_combined_value(value)
    return stack[-1] if stack else None


@mcp.tool
def list_board_dependencies(board_id: str) -> list[dict]:
    """
    List the board's dependency lines (the Red Strings edges) in one call:
    [{from, fromTitle, fromCardNumber, to, toTitle, toCardNumber, type,
    color, icon}] — the upstream route's own shape, passed through untouched
    (models/dependencies.js walks the cards server-side; archived cards are
    excluded THERE). Each line is the stored spelling from its source card —
    the board view carries NO synthesized inverse, so consumers must match
    both blocks and is-blocked-by spellings (type-inverse, consumer-side).
    The one call still returns every stored edge on the board, so gate
    logic reads this list once, not per card.

    v12.65 route facts (source-checked 2026-11-01): GET
    /api/boards/:boardId/dependencies is dependency-access gated like the
    writes; at the 9.88 low bound an auth failure can arrive as 200 + an
    embedded error body, guarded below.
    """
    raw = _wekan.get(f"/api/boards/{board_id}/dependencies") or []
    _embedded_error(raw, "list_board_dependencies")
    return [d for d in raw if isinstance(d, dict)]


@mcp.tool
def list_card_dependencies(board_id: str, card_id: str) -> list[dict]:
    """
    List one card's stored dependency entries: [{cardId, type, color, icon}]
    — the cardDependencies array as stored, passed through untouched. cardId
    is the TARGET card's id (cross-card references key on ids; card_number is
    display-only). Only the source card's own edges come back: for the whole
    board — or the inverse direction — call list_board_dependencies.
    """
    raw = _wekan.get(f"/api/boards/{board_id}/cards/{card_id}/dependencies") or []
    _embedded_error(raw, "list_card_dependencies")
    return [d for d in raw if isinstance(d, dict)]


@_write_tool
def add_card_dependency(
    board_id: str,
    card_id: str,
    target_card_id: str,
    type: Optional[str] = None,
    color: Optional[str] = None,
    icon: Optional[str] = None,
) -> dict:
    """
    Add one dependency edge on a card, or UPDATE the existing edge to the
    same target: the POST route is an UPSERT — a repeat add with a new
    type/color/icon rewrites that edge's properties and NEVER duplicates it
    (models/dependencies.js normalizes; source-checked 2026-11-01). The
    target must live on the same board ("Target card is not on this board"
    answers 400). Edge direction is the caller's convention; the house rule
    is is-blocked-by stored on the DEPENDENT card toward its blocker.

    type must be one of the seven upstream dependency types (related-to,
    blocks, is-blocked-by, fixes, is-fixed-by, duplicates, is-duplicated-by);
    an unknown value is rejected CLIENT-SIDE before any request, naming the
    allowed list — the create_label color-gate posture, with the server's own
    clean 400 staying the authority on upgrade drift. Omitted type/color/icon
    ride the upstream defaults (related-to, #eb144c, link). The route's body
    also accepts the dependsOn alias for the target key; this tool sends the
    cardId spelling. Returns the stored edge keyed on the source card.
    """
    if type is not None and type not in _DEPENDENCY_TYPES:
        raise WekanError(
            f"add_card_dependency: unknown type {type!r}. Allowed types: "
            f"{', '.join(_DEPENDENCY_TYPES)} — unknown types are never sent; "
            f"the server would answer 400 naming the same list."
        )
    body: dict = {"cardId": target_card_id}
    if type is not None: body["type"] = type
    if color is not None: body["color"] = color
    if icon is not None: body["icon"] = icon
    resp = _wekan.post(
        f"/api/boards/{board_id}/cards/{card_id}/dependencies", json_body=body
    ) or {}
    _embedded_error(resp, "add_card_dependency")
    if not isinstance(resp, dict) or "_id" not in resp:
        # Shape surprise: echo the request's own facts under the normalized
        # keys rather than pass an unexpected document through the schema.
        resp = {"_id": card_id}
    return {
        "id": resp.get("_id"),
        "target_card_id": resp.get("cardId") or target_card_id,
        "type": resp.get("type"),
        "color": resp.get("color"),
        "icon": resp.get("icon"),
    }


@_write_tool
def edit_card_dependency(
    board_id: str,
    card_id: str,
    target_card_id: str,
    type: Optional[str] = None,
    color: Optional[str] = None,
    icon: Optional[str] = None,
) -> dict:
    """
    Re-type or re-style the edge from a card to a target (PUT the
    target-scoped route): only the supplied properties change, and at least
    one of type/color/icon MUST be given — an empty change set is rejected
    here instead of riding the route as a no-op. type goes through the same
    client-side seven-type gate as add_card_dependency. The edge must exist
    (the route addresses it by target id); to create one use
    add_card_dependency.
    """
    if type is None and color is None and icon is None:
        raise WekanError(
            "edit_card_dependency: at least one of type/color/icon must change"
        )
    if type is not None and type not in _DEPENDENCY_TYPES:
        raise WekanError(
            f"edit_card_dependency: unknown type {type!r}. Allowed types: "
            f"{', '.join(_DEPENDENCY_TYPES)} — unknown types are never sent."
        )
    body: dict = {}
    if type is not None: body["type"] = type
    if color is not None: body["color"] = color
    if icon is not None: body["icon"] = icon
    _wekan.put(
        f"/api/boards/{board_id}/cards/{card_id}/dependencies/{target_card_id}",
        json_body=body,
    )
    return {
        "updated": True,
        "card_id": card_id,
        "target_card_id": target_card_id,
        "fields": list(body.keys()),
    }


@_write_tool
def remove_card_dependency(
    board_id: str,
    card_id: str,
    target_card_id: str,
) -> dict:
    """
    DESTRUCTIVE: remove the dependency edge from card_id to target_card_id —
    the DELETE route $pulls the entry off the source card's stored array and
    there is no undo (recreate with add_card_dependency, which re-keys the
    same edge). Only the edge is touched: neither card is archived, moved, or
    modified. Bounded to one edge per call, the house destructive-op posture
    shared with remove_rule and delete_checklist_item.
    """
    _wekan.delete(
        f"/api/boards/{board_id}/cards/{card_id}/dependencies/{target_card_id}"
    )
    return {"removed": True, "card_id": card_id, "target_card_id": target_card_id}


@mcp.tool
def preload_board(board_id: str, swimlane_titles: Optional[list[str]] = None) -> dict:
    """
    One-call whole-board preload for pickup planning: the swimlane -> list ->
    cards grouping with swimlane and list TITLES beside their ids, each card's
    checklist state, the board's dependency lines, and the label/field name
    maps — instead of a per-card fan-out. Rides a single GET of the board
    export with attachments=false (base64 file payloads are a must-skip for a
    preload) and a fields= section trim; the trim vocabulary is upstream
    models/lib/exportFields.js (board-header, labels, custom-fields,
    dependencies, sort, checklists), and unselected sections — comments,
    activities, subtasks — come back as EMPTY arrays, which is what keeps the
    document small. checklists and checklistItems are TOP-LEVEL arrays of the
    export document (models/exporter.js streams them keyed by cardId), so the
    per-card grouping below is arithmetic over one response: the exporter never
    fans out per card and neither does this tool.

    Each card carries EXACTLY eight fields: id, card_number, label_ids, slug,
    archived, sort, parent_id, checklists. Card titles and descriptions are not
    carried (the owner asked for the lean shape). checklists is
    [{id, title, items: [{title, finished}]}] filtered to the kickoff
    vocabulary — the five standard checklists Services, Type, Model(s),
    Lifecycle, Human in the Loop, plus the legacy spellings: Research stands in
    for Lifecycle on pre-cutover cards, and a legacy Lifecycle spelling is
    recognised by its item count when its title is not one of the current
    names. Any other checklist a card happens to carry stays out.

    slug comes from the card's customFields entry for the board's slug field,
    reduced by _slug_from_combined_value — the single parse authority: the
    field is an append-only stack of combined [<slug>](<session link>) lines
    (newest LAST), so a multi-line value yields the newest entry's bracketed
    text, a bare legacy value passes through unchanged, and a card without
    the field reads slug: null.

    swimlane_titles narrows the grouping to the named swimlanes — a run that
    pulls In Process alone, or In Process plus Backlog when it needs the Inbox
    context. The default (None) is every swimlane on the board. A title that
    matches nothing answers the documented empty grouping (swimlanes: []),
    never an exception — a filter miss is a data miss, a payload bound. The
    other arm is transport: an export answer that is not a board document
    (bodyless, non-JSON, or an error body the route returned at 200) fails the
    call, because this payload carries no degradation flag and an empty
    grouping is indistinguishable from an empty board — a consumer can only
    degrade around a read that actually failed. The unresolved-parent tail
    (see below) rides only the unfiltered read: a group with no declared
    swimlane has no title to match, so a filtered answer is exactly the named
    swimlanes.

    Archived cards are FLAGGED (archived: true), never silently dropped — the
    exporter includes them (imports need them) and pickup-side filtering
    belongs to the consumer. Linked cards never appear at all: the exporter's
    own card selector filters linkedId, so they are excluded upstream — that
    exclusion is a route fact, not client-side filtering.
    """
    doc = _wekan.get(
        f"/api/boards/{board_id}/export"
        "?attachments=false"
        "&fields=board-header,labels,custom-fields,dependencies,sort,checklists"
    )
    _embedded_error(doc, "preload_board")
    if not isinstance(doc, dict) or not doc:
        # A bodyless or non-JSON export body arrives as None, and a real board
        # document always carries its header, so either shape is a transport
        # failure. This layer's contract: it FAILS. The payload carries no
        # degradation flag, and an empty grouping is contractually identical to
        # an empty board, so folding a broken answer into one would let a pickup
        # walk conclude "no claimable cards", write the no-op marker and archive.
        # Failing is what makes the boards degrade law reachable — its
        # present-but-failed branch (one retry, then the per-list reads) can only
        # fire on a call that actually fails.
        raise WekanError(
            f"preload_board: the board export answer is not a board document "
            f"(got {type(doc).__name__})"
        )

    # The board header rides the export ROOT (models/exporter.js spreads the
    # board document), so labels are read from there; the name maps let a
    # consumer resolve label_ids and field ids without a second call.
    label_names = {
        l.get("_id"): l.get("name")
        for l in doc.get("labels", []) if isinstance(l, dict)
    }
    field_names = {
        cf.get("_id"): cf.get("name")
        for cf in doc.get("customFields", []) if isinstance(cf, dict)
    }
    slug_field_ids = {fid for fid, name in field_names.items() if name == "slug"}

    # Checklist state arrives in the same response as two flat arrays.
    items_by_checklist: dict = {}
    for item in doc.get("checklistItems") or []:
        if isinstance(item, dict):
            items_by_checklist.setdefault(item.get("checklistId"), []).append(item)
    kept_checklists = [
        cl for cl in doc.get("checklists") or []
        if isinstance(cl, dict)
        and (cl.get("title") in _PRELOAD_CHECKLIST_TITLES
             or len(items_by_checklist.get(cl.get("_id"), []))
             == _PRELOAD_LEGACY_LIFECYCLE_ITEMS)
    ]
    checklists_by_card: dict = {}
    for cl in kept_checklists:
        checklists_by_card.setdefault(cl.get("cardId"), []).append({
            "id": cl.get("_id"),
            "title": cl.get("title"),
            "items": [
                {"title": i.get("title"), "finished": bool(i.get("isFinished"))}
                for i in sorted(items_by_checklist.get(cl.get("_id"), []),
                                key=_sort_key)
            ],
        })

    cards_by_list: dict = {}
    dependencies: list = []
    for card in doc.get("cards", []):
        if not isinstance(card, dict):
            continue
        # Edge lines are computed from the card documents (they ride along
        # whether or not a renderer gates them); keyed on source/target ids
        # mirroring the board route's from/to naming.
        for edge in card.get("cardDependencies") or []:
            if isinstance(edge, dict):
                dependencies.append({
                    "from_id": card.get("_id"),
                    "to_id": edge.get("cardId"),
                    "type": edge.get("type"),
                    "color": edge.get("color"),
                    "icon": edge.get("icon"),
                })
        slug: Optional[str] = None
        for entry in card.get("customFields") or []:
            if isinstance(entry, dict) and entry.get("_id") in slug_field_ids:
                slug = _slug_from_combined_value(entry.get("value"))
                break
        cards_by_list.setdefault(card.get("listId"), []).append({
            "id": card.get("_id"),
            "card_number": card.get("cardNumber"),
            "label_ids": card.get("labelIds", []),
            "slug": slug,
            "archived": card.get("archived", False),
            "sort": card.get("sort"),
            "parent_id": card.get("parentId"),
            "checklists": checklists_by_card.get(card.get("_id"), []),
        })

    # Walk order is the board's own sort, everywhere. Lists with no cards are
    # not emitted (a preload is about cards); anything whose parent row the
    # document never declared keeps its unresolved id at the tail rather than
    # vanishing — the flag-not-drop discipline extended to unknown parents.
    lists_by_lane: dict = {}
    for l in sorted((x for x in doc.get("lists", []) if isinstance(x, dict)),
                    key=_sort_key):
        cards_in_list = cards_by_list.pop(l.get("_id"), None)
        if not cards_in_list:
            continue
        lists_by_lane.setdefault(l.get("swimlaneId"), []).append({
            "id": l.get("_id"),
            "title": l.get("title"),
            "cards": sorted(cards_in_list, key=_sort_key),
        })
    if cards_by_list:
        orphans = [c for group in cards_by_list.values() for c in group]
        lists_by_lane.setdefault(None, []).append(
            {"id": None, "title": None, "cards": sorted(orphans, key=_sort_key)}
        )

    # The titles are emitted, not looked up: the consumer's Test/Finished
    # membership tests read them straight off the payload. A filtered-out
    # swimlane's lists are popped and dropped here — leaving them would make a
    # filtered board read as an unknown-parent tail group.
    swimlanes: list = []
    for s in sorted((x for x in doc.get("swimlanes", []) if isinstance(x, dict)),
                    key=_sort_key):
        lists_in_lane = lists_by_lane.pop(s.get("_id"), None)
        if not lists_in_lane:
            continue
        if swimlane_titles is not None and s.get("title") not in swimlane_titles:
            continue
        swimlanes.append({
            "id": s.get("_id"),
            "title": s.get("title"),
            "lists": lists_in_lane,
        })
    # Tail groups stay in walk order — the board sort of the first list that
    # landed in them — because an id-sorted tail would reorder the board. An
    # unresolved parent has no title to match, so it rides only the unfiltered
    # read: a filter is a payload bound, and with one the answer is exactly the
    # named swimlanes.
    if swimlane_titles is None:
        for key, lists_in_lane in lists_by_lane.items():
            swimlanes.append({"id": key, "title": None, "lists": lists_in_lane})

    return {
        "board_id": board_id,
        "swimlanes": swimlanes,
        "dependencies": dependencies,
        "label_names": label_names,
        "field_names": field_names,
    }


@_write_tool
def set_card_labels(
    board_id: str,
    card_ids: list[str],
    add_label_ids: Optional[list[str]] = None,
    remove_label_ids: Optional[list[str]] = None,
) -> dict:
    """
    Apply and/or remove board labels across cards in ONE bulk POST — the
    missing piece behind label inheritance for follow-up cards, retiring the
    rules-engine round-trip previously needed for card labels. An omitted
    list is a no-op: add-only and remove-only calls are both legal, and each
    list is applied independently by the route (server/models/cards.js bulk
    labels route, v12.65: write-access gated, label ids validated against the
    board, at most 500 cards per call).

    The cap is enforced client-side BEFORE the request (over-cap batches fail
    with the cap named, not a bare 4xx), and the label ids are checked
    against the board's own labels first — a typo'd id names itself instead
    of silently matching nothing. The route's board-membership gate stays the
    authority; this read only fails fast. Returns the request echo (the route
    answers an acknowledgement, nothing per-card).
    """
    if not card_ids:
        return {"applied": False, "reason": "no cards listed"}
    if len(card_ids) > _BULK_LABEL_CARD_CAP:
        raise WekanError(
            f"set_card_labels: {len(card_ids)} cards exceeds the bulk route's "
            f"{_BULK_LABEL_CARD_CAP}-card cap; split the call"
        )
    wanted = list(add_label_ids or []) + list(remove_label_ids or [])
    if wanted:
        board = _wekan.get(f"/api/boards/{board_id}") or {}
        _embedded_error(board, "set_card_labels")
        known = {
            l.get("_id") for l in board.get("labels", []) if isinstance(l, dict)
        }
        unknown = sorted({lid for lid in wanted if lid not in known})
        if unknown:
            raise WekanError(
                f"set_card_labels: label ids not on board {board_id}: "
                f"{', '.join(unknown)}"
            )
    _wekan.post(
        f"/api/boards/{board_id}/cards/labels",
        json_body={
            "cardIds": card_ids,
            "addLabelIds": add_label_ids or [],
            "removeLabelIds": remove_label_ids or [],
        },
    )
    return {
        "applied": True,
        "card_count": len(card_ids),
        "add_label_ids": add_label_ids or [],
        "remove_label_ids": remove_label_ids or [],
    }


def main() -> None:
    host = os.environ.get("WEKAN_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("WEKAN_MCP_PORT", "8080"))
    log.info("serving streamable-http on %s:%d", host, port)
    try:
        mcp.run(transport="streamable-http", host=host, port=port)
    finally:
        _wekan.close()


if __name__ == "__main__":
    main()
