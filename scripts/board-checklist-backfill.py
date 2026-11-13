#!/usr/bin/env python3
"""board-checklist-backfill.py — offline, additive-only backfill planner for
existing cards' checklists, targeting the generation `provision-board.py`
ships.

Input is a board export (schema `wekan-board-export/1`), never the live
board: the plan is computed with zero network calls and printing it IS the
dry run. Writes happen only under `--apply --yes --backup-confirmed <ref>`
— bulk card mutation stays owner-executed, the backup asserted by flag.

Why additive-only, encoded in the shape of this module: removing a
checklist cascades every item row and with them the per-card tick history
(upstream #6816), and item updates accept no sort, so no option removes,
replaces, reorders or renumbers anything — there is no flag that could.
New items arrive with an explicit negative `sort` (honoured on insert
since upstream #6544) and existing items keep their stored sorts, so an
applied plan is resumable: the next dry run dedupes every landed insert to
a no-op and shows only the remainder.

Why the vocabulary is imported, never restated: the item lists come from
`provision-board.py`'s `CHECKLIST_SPEC` resolved next to THIS script, so a
generation change lands in one source-of-truth file and this engine
follows it; a pasted copy would drift silently. One file by contract: the
suite probes that coupling with a scratch copy of exactly this script and
its provision sibling, so a split would break the probe.

Scope law: live, non-archived cards outside the In Process swimlane are
the repair targets; a missing-Lifecycle or duplicated-set card is REPORTED
with its ids, never repaired — the board owner's call. Carried names
(whitespace/case-folded) dedupe to no-ops; tick state is never written.
"""

import argparse
import collections
import importlib.util
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

BOARD_SCHEMA = "wekan-board-export/1"
IN_PROCESS_SWIMLANE = "In Process"
CANCELLED_LIST = "Cancelled"
PRIORITY_FIELD = "Priority"
# A title SELECTION, not a vocabulary copy: the item lists behind these
# titles are imported from the provision spec. Type and Model(s) are
# consumed as-is and the legacy Research checklist is a documented
# consumer, so none of them is an additive leg here.
MANAGED_CHECKLISTS = ("Lifecycle", "Human in the Loop", "Services")


def fail(message):
    print(f"board-checklist-backfill: {message}", file=sys.stderr)
    raise SystemExit(2)


def norm(title):
    return re.sub(r"\s+", " ", str(title)).strip().lower()


def load_generation():
    """Return (title -> items, rules-artifact path). Resolution anchors on
    `__file__`, not the cwd, so a scratch copy with an edited provision
    sibling follows that generation."""
    source = Path(__file__).resolve().with_name("provision-board.py")
    if not source.is_file():
        fail(f"vocabulary source {source} missing — the engine imports its "
             "target lists, it never restates them")
    module_spec = importlib.util.spec_from_file_location("provision_board", source)
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return ({title: list(entry["items"]) for title, entry in module.CHECKLIST_SPEC.items()},
            module.RULES_ARTIFACT)


def load_board(path):
    try:
        with open(path, encoding="utf-8") as handle:
            board = json.load(handle)
    except OSError as exc:
        fail(f"cannot read export {path}: {exc.strerror or exc}")
    except json.JSONDecodeError as exc:
        fail(f"export {path} is not valid JSON: {exc}")
    if not isinstance(board, dict) or board.get("schema") != BOARD_SCHEMA:
        fail(f"export {path} is not a {BOARD_SCHEMA} object — the engine reads pinned export "
             "shapes; a schema change needs deliberate support, not a silently misread plan")
    if not isinstance(board.get("cards"), list) or not isinstance(board.get("lists"), list):
        fail("export needs `cards` and `lists` arrays")
    return board


def card_num(card):
    try:
        return int(card.get("num"))
    except (TypeError, ValueError):
        return 0


def select_cards(board, args):
    """(in-scope cards, exclusion counts per reason): `--card` narrows
    exclusively, `--include-list` overrides the list-level defaults
    (Cancelled, In Process swimlane), archived stays absolute."""
    lists = {str(entry.get("_id")): entry for entry in board["lists"]}
    swimlanes = {str(entry.get("_id")): entry for entry in board.get("swimlanes") or []}
    include = {norm(title) for title in args.include_list}
    exclude = {norm(title) for title in args.exclude_list}
    narrow = set(args.card)
    selected, excluded = [], collections.Counter()
    for card in board["cards"]:
        entry = lists.get(str(card.get("listId"))) or {}
        swimlane = swimlanes.get(str(entry.get("swimlaneId"))) or {}
        title = str(entry.get("title") or "")
        if card.get("archived"):
            excluded["archived"] += 1
        elif str(card.get("_id")) in narrow or norm(title) in include:
            selected.append(card)
        elif narrow:
            excluded["outside the --card set"] += 1
        elif norm(swimlane.get("title") or "") == norm(IN_PROCESS_SWIMLANE):
            excluded["In Process swimlane"] += 1
        elif norm(title) == norm(CANCELLED_LIST):
            excluded["Cancelled"] += 1
        elif norm(title) in exclude:
            excluded[f"--exclude-list {title}"] += 1
        else:
            selected.append(card)
    return selected, excluded


def new_sorts(count):
    """Ascending negative sorts for `count` inserts, in spec order.

    Negative because stored sorts are positive and consumers render
    ascending: the inserts lead, where the two gated stage names belong.
    Trailing names lead too — stored items are never renumbered; the
    runbook read-back owns that ordering pass.
    """
    return list(range(-count, 0))


def insert_action(card, checklist_id, checklist_title, item, sort, reason):
    # checklist_title is always the spec spelling: a live near-miss title
    # is a rename, renames are human-owned, and no rename leg exists here.
    return {"card": str(card.get("_id")), "card_num": card_num(card), "checklist": checklist_id,
            "checklist_title": checklist_title, "action": "add_item", "title": item,
            "sort": sort, "reason": reason}


def plan_card(card, args, items_by_title):
    """(actions, anomaly-or-None) for one selected card."""
    by_norm = {}
    for checklist in card.get("checklists") or []:
        by_norm.setdefault(norm(checklist.get("title")), []).append(checklist)
    duplicates = sorted(str(group[0].get("title")) for group in by_norm.values() if len(group) > 1)
    if duplicates:
        return [], {"kind": "duplicated-checklist-set",
                    "detail": f"title collides across {', '.join(duplicates)} — dedupe is a human merge"}
    if norm("Lifecycle") not in by_norm and not args.create_missing_lifecycle:
        return [], {"kind": "missing-lifecycle", "detail": "opt in with --create-missing-lifecycle"}

    actions = []
    for title in MANAGED_CHECKLISTS:
        want = items_by_title[title]
        existing = by_norm.get(norm(title))
        if existing is None:
            actions.append({
                "card": str(card.get("_id")), "card_num": card_num(card), "checklist": None,
                "checklist_title": title, "action": "create_checklist", "sort": -(len(want) + 1),
                "reason": "checklist absent on an in-scope card",
            })
            checklist_id, missing, leg_reason = None, want, "item on a checklist this plan creates"
        else:
            checklist_id = str(existing[0].get("_id"))
            carried = {norm(item.get("title")) for item in (existing[0].get("items") or [])}
            missing = [item for item in want if norm(item) not in carried]
            leg_reason = "missing item on an existing checklist"
        actions.extend(
            insert_action(card, checklist_id, title, item, sort, leg_reason)
            for item, sort in zip(missing, new_sorts(len(missing)))
        )
    if args.priority_default is not None:
        explicit = any(
            norm(field.get("name")) == norm(PRIORITY_FIELD) and field.get("value") is not None
            for field in card.get("custom_fields") or []
        )
        if not explicit:
            actions.append({
                "card": str(card.get("_id")), "card_num": card_num(card), "checklist": None,
                "checklist_title": None, "action": "set_priority", "field": PRIORITY_FIELD,
                "value": int(args.priority_default),
                "reason": "unset field only — an explicit value is never overwritten",
            })
    return actions, None


def sort_key(action):
    """Global plan order: card number, card id, checklist title, sort. The
    sort value orders within a group (a create precedes its items at
    -(n+1)); no key reads wall-clock input."""
    return (action["card_num"], action["card"],
            (action.get("checklist_title") or "").lower(), action.get("sort", 0))


def build_report(board, args, items_by_title, rules_artifact, state):
    """Human report: scope math, per-leg counts, legacy carriers, anomalies,
    preserved ticks, rule-drift reminder. `state` carries the planning pass."""
    legs = collections.Counter(action["action"] for action in state["actions"])
    carriers = collections.Counter()
    for card in state["processed"]:
        for checklist in card.get("checklists") or []:
            size = len(checklist.get("items") or [])
            for spec_title in MANAGED_CHECKLISTS:
                if (norm(checklist.get("title")) == norm(spec_title)
                        and size != len(items_by_title[spec_title])):
                    carriers[f"{spec_title}: {size} items (spec {len(items_by_title[spec_title])})"] += 1
    managed = {norm(title) for title in MANAGED_CHECKLISTS}
    research = sum(1 for card in state["selected"]
                   if any(norm(cl.get("title")) == "research" for cl in card.get("checklists") or []))
    ticked = sorted(f"{card.get('_id')} (#{card_num(card)})" for card in state["processed"]
                    if any(norm(cl.get("title")) in managed
                           and any(item.get("isFinished") for item in cl.get("items") or [])
                           for cl in card.get("checklists") or []))
    lines = ["board-checklist-backfill report", "",
             f"cards in export: {len(board['cards'])}; in scope: {len(state['selected'])}"]
    lines += [f"  excluded: {reason} x{count}" for reason, count in sorted(state["excluded"].items())]
    lines += ["", "per-leg counts: " + (", ".join(f"{name} x{count}" for name, count in sorted(legs.items())) or "none"),
              f"legacy Research checklists left in place (documented consumers): x{research}",
              "legacy-generation carriers:"]
    lines += [f"  {key} x{count}" for key, count in sorted(carriers.items())] or ["  none"]
    lines += ["", "anomalies — reported, never repaired:"]
    lines += [f"  {detail['kind']}: {card.get('_id')} (#{card_num(card)}) — {detail['detail']}"
              for card, detail in state["anomalies"]] or ["  none"]
    lines += [f"cards whose ticks this plan preserves without writing them: {', '.join(ticked) or 'none'}"]
    if args.priority_default is None:
        lines.append("priority leg: OFF (opt in with --priority-default N)")
    lines += ["", f"reminder: the provision dry-run keeps reporting createCard rule drift until "
                  f"the owner imports {rules_artifact}; that drift report is the provision engine "
                  f"working, not a defect."]
    return "\n".join(lines) + "\n"


def request_json(ctx, path, payload=None, method="POST"):
    """One POST/PUT (payload) or GET against the live board; returns the parsed body.

    HTTP 200 does not mean success on WeKan — several routes answer 200
    with an embedded error object, so the body is the verdict.
    """
    request = urllib.request.Request(
        ctx["base"] + path,
        data=None if payload is None else json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {ctx['token']}", "Content-Type": "application/json"},
        method="GET" if payload is None else method,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode("utf-8", "replace")
    try:
        body = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"unparseable response body: {text[:200]!r}") from exc
    if isinstance(body, dict) and ("error" in body or body.get("success") is False):
        raise RuntimeError(f"embedded error in 200 response: {body}")
    return body


def live_target():
    base, token = (os.environ.get("WEKAN_URL") or "").rstrip("/"), os.environ.get("WEKAN_TOKEN") or ""
    if not base or not token:
        fail("--apply needs WEKAN_URL and WEKAN_TOKEN in the environment (env names only; a value is never committed, echoed or logged)")
    return base, token


def resolve_checklist(ctx, card_id, title):
    answer = request_json(ctx, f"/api/boards/{ctx['board_id']}/cards/{card_id}/checklists")
    entries = answer if isinstance(answer, list) else answer.get("checklists") or []
    for entry in entries:
        if norm(entry.get("title")) == norm(title):
            return str(entry.get("_id"))
    raise RuntimeError(f"created checklist {title!r} not readable back on card {card_id}")


def resolve_priority_field(ctx):
    for entry in ctx["board"].get("custom_fields") or []:
        if norm(entry.get("name")) == norm(PRIORITY_FIELD):
            return str(entry["_id"])
    answer = request_json(ctx, f"/api/boards/{ctx['board_id']}/custom-fields")
    entries = answer if isinstance(answer, list) else answer.get("customFields") or []
    for entry in entries:
        if norm(entry.get("name")) == norm(PRIORITY_FIELD):
            return str(entry["_id"])
    raise RuntimeError("no Priority custom field on the board — the priority leg cannot run")


def run_action(ctx, action):
    """Execute one planned write, POST/PUT-only; apply-time id caches live in ctx."""
    if action["action"] == "create_checklist":
        answer = request_json(ctx, f"/api/boards/{ctx['board_id']}/cards/{action['card']}/checklists",
                              {"title": action["checklist_title"], "items": []})
        new_id = str(answer.get("_id") or answer.get("checklistId") or "") if isinstance(answer, dict) else ""
        ctx["created"][(action["card"], norm(action["checklist_title"]))] = new_id or resolve_checklist(
            ctx, action["card"], action["checklist_title"])
        return
    if action["action"] == "add_item":
        checklist_id = action["checklist"] or ctx["created"].get(
            (action["card"], norm(action["checklist_title"])))
        if not checklist_id:
            raise RuntimeError(f"no checklist id resolved for {action['checklist_title']!r}")
        request_json(ctx, f"/api/boards/{ctx['board_id']}/cards/{action['card']}/checklists/{checklist_id}/items",
                     {"title": action["title"], "sort": action["sort"]})
        return
    card = request_json(ctx, f"/api/cards/{action['card']}")
    list_id = str(card.get("listId") or "")
    if not list_id:
        raise RuntimeError(f"card {action['card']} has no listId — the priority write has no list-scoped target")
    if "field" not in ctx:
        ctx["field"] = resolve_priority_field(ctx)
    fid = ctx["field"]
    entries = [entry for entry in (card.get("customFields") or []) if entry]
    # The value route silently no-ops on fields the card does not already
    # carry (v9.99), so an unattached card takes the whole-array PUT leg.
    if any(entry.get("_id") == fid for entry in entries):
        request_json(ctx, f"/api/boards/{ctx['board_id']}/lists/{list_id}/cards/{action['card']}/customFields/{fid}",
                     {"value": action["value"]})
        return
    entries.append({"_id": fid, "value": action["value"]})
    request_json(ctx, f"/api/boards/{ctx['board_id']}/lists/{list_id}/cards/{action['card']}",
                 {"customFields": entries}, method="PUT")


def action_line(action):
    where = f"card {action['card_num']} [{action['card']}] {action['checklist_title'] or action.get('field')}"
    if action["action"] == "add_item":
        return f"{where} add_item {action['title']!r} sort {action['sort']}"
    if action["action"] == "create_checklist":
        return f"{where} create_checklist"
    return f"{where} set_priority {action['value']}"


def abort(index, completed, error):
    # The completed log is the owner's read-back of exactly what landed.
    print(f"board-checklist-backfill: ABORT at attempt {index}: {error}\n"
          f"completed before abort ({len(completed)}):\n"
          + "".join(f"  {done}\n" for done in completed)
          + "rerun the dry plan to see the remainder — landed inserts dedupe to no-ops, "
            "so the plan is resumable by construction.", file=sys.stderr, flush=True)
    raise SystemExit(3)


def apply_plan(plan, board):
    ctx = {"created": {}, "board": board}
    ctx["base"], ctx["token"] = live_target()
    ctx["board_id"] = str((board.get("board") or {}).get("_id") or "")
    if not ctx["board_id"]:
        fail("export carries no board _id — the live leg cannot resolve targets")
    completed = []
    for index, action in enumerate(plan, 1):
        line = action_line(action)
        print(f"attempt {index}/{len(plan)}: {line}", file=sys.stderr, flush=True)
        try:
            run_action(ctx, action)
        except (urllib.error.URLError, RuntimeError, OSError) as exc:
            abort(index, completed, exc)
        completed.append(line)
    print(f"apply complete: {len(completed)} actions executed", file=sys.stderr)


def parse_args():
    parser = argparse.ArgumentParser(
        prog="board-checklist-backfill.py",
        description="Plan (default) or, under the triple-flag owner guard, apply the additive "
        "in-place expansion of existing cards' Lifecycle / Human in the Loop / Services "
        "checklists onto the provision spec. Insert-only by construction, tick state is never "
        "a write target, and a dry run performs zero network calls.",
    )
    parser.add_argument("--board", required=True, help=f"Path to a {BOARD_SCHEMA} export JSON")
    parser.add_argument("--out", help="Write the plan JSON array to this file (stdout still carries it)")
    parser.add_argument("--report", help="Write the human report to this file (also printed on stderr)")
    parser.add_argument("--dry-run", action="store_true", help="Accepted no-op: planning IS the default run.")
    parser.add_argument("--apply", action="store_true", help="Live leg — runs only with BOTH --yes and --backup-confirmed")
    parser.add_argument("--yes", action="store_true", help="Owner confirmation marker")
    parser.add_argument("--backup-confirmed", metavar="REF",
                        help="Name of the board backup taken before applying")
    parser.add_argument("--include-list", action="append", default=[], metavar="TITLE",
                        help="Force-include cards on this list title, overriding the list-level defaults (archived stays excluded)")
    parser.add_argument("--exclude-list", action="append", default=[], metavar="TITLE",
                        help="Additionally exclude cards on this list title")
    parser.add_argument("--card", action="append", default=[], metavar="ID",
                        help="Repeatable narrow-target escape hatch: plan only these card ids")
    parser.add_argument("--create-missing-lifecycle", action="store_true",
                        help="Turn the missing-Lifecycle anomaly from report-only into a create leg")
    parser.add_argument("--priority-default", type=int, metavar="N",
                        help="Numeric Priority writes for cards whose field is unset; default off")
    args = parser.parse_args()
    if args.apply and (not args.yes or args.backup_confirmed is None):
        parser.error("--apply needs BOTH --yes and --backup-confirmed <ref>; refusing before writing anything")
    return args


def main():
    args = parse_args()
    items_by_title, rules_artifact = load_generation()
    board = load_board(args.board)
    selected, excluded = select_cards(board, args)
    selected.sort(key=lambda card: (card_num(card), str(card.get("_id"))))
    actions, anomalies, processed = [], [], []
    for card in selected:
        card_actions, anomaly = plan_card(card, args, items_by_title)
        if anomaly is None:
            processed.append(card)
        else:
            anomalies.append((card, anomaly))
        actions.extend(card_actions)
    actions.sort(key=sort_key)

    report = build_report(board, args, items_by_title, rules_artifact,
                          {"selected": selected, "processed": processed, "anomalies": anomalies,
                           "actions": actions, "excluded": excluded})
    sys.stderr.write(report)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as handle:
            handle.write(report)
    if args.priority_default is not None:
        print("priority leg armed — this is the owner-run bulk path: the numeric writes cover "
              "only cards whose Priority reads unset, and an agent's own per-card stamp is a "
              "separate permission — never a sweep authorization.", file=sys.stderr)

    plan_text = json.dumps(actions, indent=2, ensure_ascii=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(plan_text + "\n")
    print(plan_text)

    if args.apply:
        apply_plan(actions, board)


if __name__ == "__main__":
    main()
