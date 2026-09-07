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
    - Destructive tools (delete_board, delete_card) are intentionally OMITTED.
      remove_rule is the one destructive tool that IS exposed (rules are
      cheap to recreate and needed for automation hygiene); its docstring
      marks it as destructive. Add the others back only if you want them,
      and mark with destructive hints.
    - WEKAN_MCP_READ_ONLY=true hides every write tool from the catalog
      (they are never registered), for the readonly server tier.

Transport: streamable-http on 0.0.0.0:8080 (chosen for Kubernetes;
    ToolHive proxies this to Claude Desktop / other clients).
"""

from __future__ import annotations

import logging
import os
import sys
from typing import Optional

from fastmcp import FastMCP

from wekan_mcp.wekan import WekanClient, WekanError


# ---------- Logging (stderr only; stdout may be reserved for stdio transport) ----------

logging.basicConfig(
    stream=sys.stderr,
    level=os.environ.get("WEKAN_MCP_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("wekan-mcp")


# ---------- Read-only mode ----------

# Set WEKAN_MCP_READ_ONLY=true on the readonly server tier: write tools are
# then never registered (hidden from tools/list, impossible to call). The
# admin tier leaves it unset and gets the full read+write surface.
READ_ONLY = os.environ.get("WEKAN_MCP_READ_ONLY", "").strip().lower() in (
    "1", "true", "yes", "on",
)


# ---------- Startup: validate credential ONCE ----------

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


# ---------- Response shaping helpers ----------

def _slim_board(b: dict) -> dict:
    """Board with only what the model actually needs to reason about it."""
    return {
        "id": b.get("_id"),
        "title": b.get("title"),
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
    return {
        "id": r.get("_id"),
        "title": r.get("title"),
        "trigger": r.get("trigger"),
        "action": r.get("action"),
    }


# ==============================================================================
# READ TOOLS
# ==============================================================================

@mcp.tool
def list_boards() -> list[dict]:
    """List the boards the WeKan service user is a member of."""
    raw = _wekan.get(f"/api/users/{_wekan.user_id}/boards") or []
    # This endpoint returns {_id, title} pairs; fetch nothing else.
    return [{"id": b.get("_id"), "title": b.get("title")} for b in raw]


@mcp.tool
def get_board(board_id: str) -> dict:
    """Get a board's metadata: title, permission, color, labels."""
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
    """List the cards in a specific list."""
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
    """List the automation rules of a board. Each rule embeds its trigger and
    action inline (e.g. trigger {activityType: moveCard, listName: Doing} +
    action {actionType: addMember, username: ...}). Rule ids are required by
    get_rule, update_rule and remove_rule."""
    raw = _wekan.get(f"/api/boards/{board_id}/rules") or []
    return [_slim_rule(r) for r in raw]


@mcp.tool
def get_rule(board_id: str, rule_id: str) -> dict:
    """Get one automation rule with its full embedded trigger and action."""
    return _slim_rule(_wekan.get(f"/api/boards/{board_id}/rules/{rule_id}") or {})


# ==============================================================================
# WRITE TOOLS (skipped entirely when WEKAN_MCP_READ_ONLY is set)
# ==============================================================================

@_write_tool
def create_card(
    board_id: str,
    list_id: str,
    swimlane_id: str,
    title: str,
    description: str = "",
) -> dict:
    """
    Create a card in a specific list and swimlane. The service user is used
    as the card author. Returns the new card's id and title.
    """
    body = {
        "title": title,
        "description": description,
        "authorId": _wekan.user_id,
        "swimlaneId": swimlane_id,
    }
    resp = _wekan.post(f"/api/boards/{board_id}/lists/{list_id}/cards", json_body=body) or {}
    return {"id": resp.get("_id"), "title": title}


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


# ==============================================================================
# Entrypoint
# ==============================================================================

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
