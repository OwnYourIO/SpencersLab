#!/usr/bin/env python3
"""provision-board.py — offline board-provisioning engine for the AI-Dev board.

Reads a board snapshot (wekan-board-snapshot/1 JSON: swimlanes, lists,
labels, rules) and prints the ordered, idempotent action list that brings
the board to the built-in spec: the Backlog→Planning list mirror, one
`Bucket: <list>` label plus a createCard/moveCard rule pair per Planning
list, the Provider: API / Provider: Local labels, and the Inbox ensure.
Printing the plan IS the dry run (C01 AC5): this engine never applies —
no network module, no credential argument, no environment read (C01 AC4) —
because agent sessions hold no board credentials and every mutation is
gated by the wekan-board-provision skill's human confirmation.

Why one label and two rules per list: WeKan rule actions take a fixed
labelId with no variable substitution, so no generic "Bucket: {listname}"
rule exists, and a created card fires createCard, not moveCard (RESEARCH
F1). The `swimlaneName: Planning` matcher in every emitted trigger is
load-bearing: identical list titles exist as separate list documents in
Backlog and Farm, and an unscoped rule would cross-fire into them.

Everything keys on titles: snapshot ids are realism for the apply step,
which resolves them live. Matching is case-insensitive and the engine only
adds — existing lists, labels, and rules are never renamed, recolored, or
deleted, so the human typo list `Outside Proccess` in Farm and any board
color an owner changed survive untouched.
"""

import argparse
import json
import sys

SOURCE_SWIMLANE = "Backlog"
TARGET_SWIMLANE = "Planning"
INBOX_LIST = "Inbox"
BUCKET_PREFIX = "Bucket: "
# The board's "Bucket Color" label carries this swatch; bucket labels
# inherit it (card #90 ruling).
BUCKET_COLOR = "darkgreen"
# Provider colors are palette defaults, not pinned intent: presence is
# judged by name only, so an apply never recolors a label an owner changed.
PROVIDER_LABELS = (("Provider: API", "purple"), ("Provider: Local", "yellow"))
RULE_ACTIVITIES = ("createCard", "moveCard")
# U+2014 separator: the rule-title convention the board's bucket rules use,
# e.g. "Bucket: Context — createCard".
RULE_TITLE_SEP = " — "
SNAPSHOT_SCHEMA = "wekan-board-snapshot/1"


def fail(message):
    print(f"provision-board: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_snapshot(path):
    try:
        with open(path, encoding="utf-8") as fh:
            snapshot = json.load(fh)
    except OSError as exc:
        fail(f"cannot read fixture {path}: {exc.strerror or exc}")
    except json.JSONDecodeError as exc:
        fail(f"fixture {path} is not valid JSON: {exc}")
    if not isinstance(snapshot, dict):
        fail(f"fixture {path} must be a wekan-board-snapshot/1 object")
    if snapshot.get("schema") != SNAPSHOT_SCHEMA:
        fail(f"fixture {path} has schema {snapshot.get('schema')!r}, "
             f"want {SNAPSHOT_SCHEMA!r} — the engine reads one snapshot shape; "
             "a schema change needs deliberate support here, not a silently misread diff")
    return snapshot


def swimlane_titles(snapshot, swimlane_name):
    """List titles of one swimlane, snapshot order.

    `swimlanes` maps name→id and `lists` maps id→titles; the pair is the
    only route from a swimlane name to its lists.
    """
    swimlanes = snapshot.get("swimlanes")
    lists = snapshot.get("lists")
    if not isinstance(swimlanes, dict) or not isinstance(lists, dict):
        fail("snapshot needs `swimlanes` (name→id) and `lists` (id→titles) maps")
    if swimlane_name not in swimlanes:
        fail(f"snapshot has no {swimlane_name!r} swimlane")
    return [str(title) for title in lists.get(swimlanes[swimlane_name]) or []]


def mirror_titles(backlog_titles):
    """Backlog titles minus Inbox, deduplicated case-insensitively.

    Inbox is a parking list, never a bucket: the first ruling excludes it
    from the Planning mirror (C01 AC3).
    """
    mirror, seen = [], set()
    for title in backlog_titles:
        key = title.lower()
        if key == INBOX_LIST.lower() or key in seen:
            continue
        seen.add(key)
        mirror.append(title)
    return mirror


def existing_rule_keys(rules):
    """Case-folded identity of every rule already on the board.

    A rule counts under its own title and, when trigger AND action
    together pin this spec's bucket rule (a Planning-scoped
    createCard/moveCard adding that list's own Bucket label), under the
    canonical bucket title — so an applied rule still matches even if its
    stored title drifted. A Planning-scoped activity alone is not a
    bucket rule: a human checklist or notification rule on a mirrored
    list must not cancel the pair the spec wants to add. WeKan's "*"
    means "any", not "planning" or a list name, so wildcard triggers
    contribute no canonical key.
    """
    keys = set()
    for rule in rules or []:
        if not isinstance(rule, dict):
            continue
        keys.add(str(rule.get("title") or "").strip().lower())
        trigger = rule.get("trigger") or {}
        if str(trigger.get("swimlaneName") or "").strip().lower() != TARGET_SWIMLANE.lower():
            continue
        activity = str(trigger.get("activityType") or "").strip()
        list_name = str(trigger.get("listName") or "").strip()
        bucket_label = f"{BUCKET_PREFIX}{list_name}"
        adds_bucket = str((rule.get("action") or {}).get("addLabel") or "")
        if (list_name and adds_bucket.strip().lower() == bucket_label.lower()
                and activity.lower() in (a.lower() for a in RULE_ACTIVITIES)):
            keys.add(f"{bucket_label}{RULE_TITLE_SEP}{activity}".lower())
    return keys


def plan_actions(snapshot):
    backlog_titles = swimlane_titles(snapshot, SOURCE_SWIMLANE)
    planning_titles = swimlane_titles(snapshot, TARGET_SWIMLANE)
    planning_seen = {title.lower() for title in planning_titles}
    mirror = mirror_titles(backlog_titles)

    actions = []
    if INBOX_LIST.lower() not in {title.lower() for title in backlog_titles}:
        actions.append({"action": "create_list", "title": INBOX_LIST, "swimlane": SOURCE_SWIMLANE})
    for title in mirror:
        if title.lower() not in planning_seen:
            actions.append({"action": "create_list", "title": title, "swimlane": TARGET_SWIMLANE})

    label_seen = {name.lower() for name in (snapshot.get("labels") or {})}
    rule_seen = existing_rule_keys(snapshot.get("rules"))
    for title in mirror:
        bucket_label = f"{BUCKET_PREFIX}{title}"
        if bucket_label.lower() not in label_seen:
            actions.append({"action": "create_label", "name": bucket_label, "color": BUCKET_COLOR})
        for activity in RULE_ACTIVITIES:
            rule_title = f"{bucket_label}{RULE_TITLE_SEP}{activity}"
            if rule_title.lower() in rule_seen:
                continue
            actions.append({
                "action": "create_rule",
                "title": rule_title,
                "trigger": {"activityType": activity, "listName": title, "swimlaneName": TARGET_SWIMLANE},
                "label": bucket_label,
            })
    for name, color in PROVIDER_LABELS:
        if name.lower() not in label_seen:
            actions.append({"action": "create_label", "name": name, "color": color})
    return actions


def render_text(action):
    kind = action["action"]
    if kind == "create_list":
        return f'create_list "{action["title"]}" into {action["swimlane"]}'
    if kind == "create_label":
        return f'create_label "{action["name"]}" ({action["color"]})'
    trigger = action["trigger"]
    return (f'create_rule "{action["title"]}": on {trigger["activityType"]} in list '
            f'"{trigger["listName"]}" ({trigger["swimlaneName"]} swimlane) add label "{action["label"]}"')


def parse_args():
    parser = argparse.ArgumentParser(
        description="Diff a WeKan board snapshot against the built-in provisioning spec and print "
        "the idempotent action plan. Printing the plan IS the dry run; applying belongs to the "
        "wekan-board-provision skill.",
    )
    parser.add_argument("--fixture", required=True, help="Path to a wekan-board-snapshot/1 JSON file")
    parser.add_argument("--format", choices=("json", "text"), default="json", help="Plan output shape")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Accepted no-op: the engine never applies, so every run is the dry run.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    actions = plan_actions(load_snapshot(args.fixture))
    if args.format == "json":
        print(json.dumps(actions, indent=2, ensure_ascii=False))
    elif actions:
        print("\n".join(render_text(action) for action in actions))
    else:
        print("no actions — snapshot already satisfies the spec")


if __name__ == "__main__":
    main()
