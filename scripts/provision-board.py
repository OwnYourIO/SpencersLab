#!/usr/bin/env python3
"""provision-board.py — offline board-provisioning engine for the AI-Dev board.

Reads a board snapshot (schema `wekan-board-snapshot/1`: swimlanes, lists,
labels, rules; schema `wekan-board-snapshot/2` additionally carries the
createCard rule's `checklist_extras`) and prints the ordered, idempotent
action list that brings the board to the built-in spec: the Backlog→Planning
list mirror, one `Bucket: <list>` label plus a createCard/moveCard rule pair
per Planning list, the Provider: API / Provider: Local and Research: Parallel
labels, the Inbox ensure, and — schema 2 only — the createCard checklist
spec diff. Printing the plan IS the dry run (C01 AC5): this engine never
applies — no network module, no credential argument, no environment read
(C01 AC4) — because agent sessions hold no board credentials and every
mutation is gated by the wekan-board-provision skill's human confirmation.

Why one label and two rules per list: WeKan rule actions take a fixed
labelId with no variable substitution, so no generic "Bucket: {listname}"
rule exists, and a created card fires createCard, not moveCard (RESEARCH
F1). The `swimlaneName: Planning` matcher in every emitted trigger is
load-bearing: identical list titles exist as separate list documents in
Backlog and Farm, and an unscoped rule would cross-fire into them.

Why the checklist diff emits a runbook entry instead of an applicable
action: WeKan rule checklist extras are creatable only through the UI
wizard or Rules → Import JSON — never REST (v12-upgrade research) — so the
cutover's apply leg belongs to a human taking a board backup first, and the
engine's role ends at naming the artifact. Against a schema-1 snapshot the
extras cannot be verified at all: the engine prints an UNVERIFIABLE note on
stderr instead of an action, because a note is not an action — idempotence
of the zero-action re-run must not depend on what a snapshot failed to
capture.

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
# Same posture for the parallel-research label the coord loop keys on
# (C06's per-ask research split); orange is the palette default — the owner
# may recolor, the plan only ensures existence by name.
PARALLEL_LABEL = ("Research: Parallel", "orange")
RULE_ACTIVITIES = ("createCard", "moveCard")
# U+2014 separator: the rule-title convention the board's bucket rules use,
# e.g. "Bucket: Context — createCard".
RULE_TITLE_SEP = " — "
SNAPSHOT_SCHEMA = "wekan-board-snapshot/1"
SNAPSHOT_SCHEMA_V2 = "wekan-board-snapshot/2"

# The Lifecycle stage names exactly as C07 landed them in the boards skill
# (`.rulesync/skills/boards/SKILL.md`) — that text is the authority, copied
# not retyped (the cf96 cutover suite pins the equality and fails loudly on
# drift). Ten stages plus Single Session LAST (OQ6 ruling), Human in the
# Loop mirrors the same eleven names (OQ6 derived), and the createCard
# extras arrive with ONLY Model(s) → Qwen Flash checked (OQ13 ruling) so
# blank Lifecycle/HITL defaults govern. Services/Type/Model(s) carry the
# v1 rule's item sets (`.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/
# board-rules-v12.64.json`).
LIFECYCLE_ITEMS = [
    "Exploration",
    "Agent Decides Research",
    "Pre Research",
    "Planning",
    "Post Research",
    "Test Writing",
    "Chunk Development",
    "Chunk Review",
    "Final Review",
    "Deployment",
    "Single Session",
]
CHECKLIST_SPEC = {
    "Services": {
        "items": [
            "backups",
            "dev",
            "gpu",
            "gpu-ai",
            "grow",
            "home",
            "infra",
            "media",
            "monitoring",
            "personal",
            "proxy-backup",
            "proxy-local",
            "proxy-remote",
            "home-assistant",
            "agent context",
        ],
        "checked": [],
    },
    "Type": {
        "items": ["feat", "bug", "debug", "dep", "refactor", "chore", "docs"],
        "checked": [],
    },
    "Model(s)": {
        "items": ["Qwen Large", "Qwen 27b", "Qwen Flash", "Local (gpu-ai)"],
        "checked": ["Qwen Flash"],
    },
    "Lifecycle": {"items": LIFECYCLE_ITEMS, "checked": []},
    "Human in the Loop": {"items": LIFECYCLE_ITEMS, "checked": []},
}
# The v2 rules-import artifact the drift action points the human at; C08
# produces it modify-only and no agent applies it (C10's runbook executes).
RULES_ARTIFACT = (
    ".agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json"
)


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
        fail("fixture must be a wekan-board-snapshot object")
    schema = snapshot.get("schema")
    if schema not in (SNAPSHOT_SCHEMA, SNAPSHOT_SCHEMA_V2):
        fail(f"fixture {path} has schema {schema!r}, "
             f"want {SNAPSHOT_SCHEMA!r} or {SNAPSHOT_SCHEMA_V2!r} — the engine reads pinned "
             "snapshot shapes; a schema change needs deliberate support here, not a "
             "silently misread diff")
    if schema == SNAPSHOT_SCHEMA_V2 and not isinstance(snapshot.get("checklist_extras"), dict):
        # A schema-2 snapshot without the map is a collector bug: guessing "no
        # extras" would emit a full drift plan from a snapshot that merely
        # failed to look.
        fail(f"fixture {path} declares {SNAPSHOT_SCHEMA_V2} but has no "
             "`checklist_extras` object — collect the createCard rule's extras "
             "or capture a schema-1 snapshot")
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


def checklist_extras_drift(extras):
    """Every createCard-extras difference between the snapshot and the spec.

    Item ORDER is part of the spec (the Lifecycle names are "in card
    order"), so items compare as lists; checked-state is a bag, so those
    compare sorted. One entry per drifted checklist, deterministic order.
    """
    drift = []
    for name in sorted(CHECKLIST_SPEC):
        want = CHECKLIST_SPEC[name]
        got = extras.get(name)
        if not isinstance(got, dict):
            drift.append(f"{name}: absent from the rule")
            continue
        got_items = [str(item) for item in (got.get("items") or [])]
        got_checked = [str(item) for item in (got.get("checked") or [])]
        if got_items != want["items"]:
            drift.append(f"{name}: items {got_items} want {want['items']}")
        if sorted(got_checked) != sorted(want["checked"]):
            drift.append(f"{name}: checked {got_checked} want {want['checked']}")
    for name in sorted(set(extras) - set(CHECKLIST_SPEC)):
        drift.append(f"{name}: on the rule but outside the spec (v2 dropped it)")
    return drift


def print_checklist_note(snapshot):
    """Schema-1 snapshots cannot verify the checklist spec — say so on stderr.

    The note never rides the action list: an unread property must not make
    every fresh schema-1 plan non-empty and break the zero-action verify.
    """
    if snapshot.get("schema") == SNAPSHOT_SCHEMA:
        print(
            "provision-board: schema-1 snapshot captures no checklist_extras, so the "
            f"createCard checklist spec is UNVERIFIABLE from it — the runbook stays the "
            f"human-executed WeKan UI → Rules → Import JSON of {RULES_ARTIFACT} "
            "(board backup first; the engine never applies)",
            file=sys.stderr,
        )


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
    for name, color in (*PROVIDER_LABELS, PARALLEL_LABEL):
        if name.lower() not in label_seen:
            actions.append({"action": "create_label", "name": name, "color": color})

    if snapshot.get("schema") == SNAPSHOT_SCHEMA_V2:
        drift = checklist_extras_drift(snapshot["checklist_extras"])
        if drift:
            actions.append({
                "action": "update_createcard_checklists",
                "artifact": RULES_ARTIFACT,
                "drift": drift,
            })
    return actions


def render_text(action):
    kind = action["action"]
    if kind == "create_list":
        return f'create_list "{action["title"]}" into {action["swimlane"]}'
    if kind == "create_label":
        return f'create_label "{action["name"]}" ({action["color"]})'
    if kind == "update_createcard_checklists":
        return (f'HUMAN-EXECUTED: WeKan UI → Rules → Import JSON {action["artifact"]} '
                f'(backup first) — createCard checklist extras drift: '
                f'{"; ".join(action["drift"])}')
    trigger = action["trigger"]
    return (f'create_rule "{action["title"]}": on {trigger["activityType"]} in list '
            f'"{trigger["listName"]}" ({trigger["swimlaneName"]} swimlane) add label "{action["label"]}"')


def parse_args():
    parser = argparse.ArgumentParser(
        description="Diff a WeKan board snapshot against the built-in provisioning spec and print "
        "the idempotent action plan. Printing the plan IS the dry run; applying belongs to the "
        "wekan-board-provision skill.",
    )
    parser.add_argument("--fixture", required=True,
                        help=f"Path to a {SNAPSHOT_SCHEMA} or {SNAPSHOT_SCHEMA_V2} JSON file")
    parser.add_argument("--format", choices=("json", "text"), default="json", help="Plan output shape")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Accepted no-op: the engine never applies, so every run is the dry run.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    snapshot = load_snapshot(args.fixture)
    print_checklist_note(snapshot)
    actions = plan_actions(snapshot)
    if args.format == "json":
        print(json.dumps(actions, indent=2, ensure_ascii=False))
    elif actions:
        print("\n".join(render_text(action) for action in actions))
    else:
        print("no actions — snapshot already satisfies the spec")


if __name__ == "__main__":
    main()
