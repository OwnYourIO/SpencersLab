#!/usr/bin/env bash
# wekan-mcp cf-96 dependency/preload/label-surface contract
# (2026/2026-10-cf-96-feat-dep-tracking-card-pickup, C01).
#
# Pins chunks/C01.md "## Tests" + AC2 + AC4: the five Red Strings dependency
# tools 1:1 to the RESEARCH 1.3 routes, the preload_board one-call export
# reshape, the set_card_labels bulk wrapper (AD-74), the _slim_card
# passthroughs, and the create_card parent_id two-step — plus the doc-parity
# re-stamp the same commit must carry. The tools.sh re-pin of the registry
# arithmetic (17+21/38) and the README/SKILL count lines land in C01's dev
# commit (doc-parity pins are never red between commits, DECISIONS
# convention); THIS file is the designed-red contract the dev implements to,
# named here because the assertions below ARE the interface.
#
# Pinned response-shape names (C01 T2/T3 interface): preload_board returns
# keys {"board_id","swimlanes","lists","cards"? no — grouped: "swimlanes"
# (each with "lists", each with "cards"), "dependencies", "label_names",
# "field_names"}; per-card dict EXACTLY {id, card_number, label_ids, slug,
# archived, sort, parent_id}; set_card_labels args (board_id, card_ids,
# add_label_ids=None, remove_label_ids=None); create_card's parent_id is the
# TRAILING parameter after default_checked.
#
# AC trace: t1[C01 AC2 — dep signatures, 7-type client gate, upsert doc,
# DESTRUCTIVE mark, registration kinds] t2[AC2 — preload reshape contract
# incl. archived-flagged-not-dropped + no title/description] t3[AC2 —
# set_card_labels bulk shape + ≤500 cap + board-label validation] t4[AC2 —
# _slim_card passthroughs + list_cards_in_list stays strip-accurate] t5[AC2 —
# create_card two-step, non-rollback, OQ1 negative: no auto-edge] t6[AC4 —
# docs re-stamped, evidence stamps source-only 2026-11, nothing live-claimed]
# t7[AC3 — wekan.py byte-unchanged (tools.sh t8 posture)]
# t8[C11 AC1 — _slim_rule 7-key capture projection: extras + enabled ride the
#     route documents un-reshaped, get_rule/list_rules stay plain @mcp.tool
#     (readonly tier), docstrings re-stamped. GREEN ON ARRIVAL after C11 dev
#     lands (red at the pre-C11 tree — the four-key projection structurally
#     cannot answer the schema-2 capture, RESEARCH F5).
#
# Red posture: t1–t5 are DESIGNED RED at authoring — verified 2026-11-01:
# none of the seven new names exists in server.py; every red names the
# missing tool/shape, never a harness fault. t6 red until the same-commit
# re-stamp; t7 green at base, HOLD (turns red the moment dev edits wekan.py).
#
# Statics-only by design (D8 / DECISIONS convention): AST + grep over the
# source, no server, no network. The live round-trip is the C10 runbook's
# user probe.
#
# Usage:
#   bash tests/wekan-mcp/dependencies.sh            # t1..t8
#   bash tests/wekan-mcp/dependencies.sh t2 t5      # subset
#   CF96_BASE=<ref> bash tests/wekan-mcp/dependencies.sh t7
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SERVER="containers/wekan-mcp/wekan_mcp/server.py"
WEKAN_PY="containers/wekan-mcp/wekan_mcp/wekan.py"
README="containers/wekan-mcp/README.md"
SKILL_MCP="skills/wekan-mcp/SKILL.md"
SHAPES="skills/wekan-mcp/references/call-shapes.md"
SKILL_API="skills/wekan-api/SKILL.md"
PIN_BASE="${CF96_BASE:-$(git merge-base main HEAD)}"

checks=0
FAILED=0
ok() { checks=$((checks + 1)); printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; exit 1; }

declare -A WANT=()
if [ "$#" -eq 0 ]; then
  for i in 1 2 3 4 5 6 7 8; do WANT["t$i"]=1; done
else
  for a in "$@"; do
    [[ "$a" =~ ^t([1-8])$ ]] || fail "unknown check id '$a' (expected t1..t8)"
    WANT["$a"]=1
  done
fi
want() { [ -n "${WANT[$1]:-}" ]; }

[ -f "$SERVER" ] || fail "harness: $SERVER missing (repo layout fault, not a C01 red)"

# --- t1: the five dependency tools (C01 T1) --------------------------------------
if want t1; then
  if ! python3 - "$SERVER" <<'PY'
import ast, re, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)

def dec_kind(fn):
    for d in fn.decorator_list:
        if isinstance(d, ast.Attribute) and d.attr == "tool" \
           and isinstance(d.value, ast.Name) and d.value.id == "mcp":
            return "read"
        if isinstance(d, ast.Name) and d.id == "_write_tool":
            return "write"
    return None

funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def seg(name):
    fn = funcs.get(name)
    if fn is None:
        print(f"t1: {name} is not defined in server.py yet — the cf-96 C01 T1 dependency block has not landed (designed red before C01 dev, not a harness fault)")
        sys.exit(1)
    return ast.get_source_segment(src, fn)

# registration kinds: 2 bare reads, 3 writes through _write_tool ONLY
for n in ("list_board_dependencies", "list_card_dependencies"):
    if n not in funcs:
        print(f"t1: {n} is not defined in server.py yet — the cf-96 C01 T1 dependency block has not landed (designed red before C01 dev, not a harness fault)")
        sys.exit(1)
    if dec_kind(funcs[n]) != "read":
        print(f"t1: {n} must be registered as a bare @mcp.tool READ (present on every tier)"); sys.exit(1)
WRITE3 = ("add_card_dependency", "edit_card_dependency", "remove_card_dependency")
for n in WRITE3:
    kind = dec_kind(funcs[n]) if n in funcs else None
    if kind != "write":
        print(f"t1: {n} must register through _write_tool (readonly tier hides writes by construction), kind seen: {kind}"); sys.exit(1)
    if "mcp.tool" in seg(n):
        print(f"t1: {n} body re-registers outside _write_tool — the AC2 negative pin"); sys.exit(1)

def args(name):
    return [(a.arg, ast.unparse(a.annotation) if a.annotation else None) for a in funcs[name].args.args]

a = args("list_board_dependencies"); 
if [x[0] for x in a] != ["board_id"]:
    print(f"t1: list_board_dependencies args {[x[0] for x in a]}, want (board_id)"); sys.exit(1)
a = args("list_card_dependencies")
if [x[0] for x in a] != ["board_id", "card_id"]:
    print(f"t1: list_card_dependencies args {[x[0] for x in a]}, want (board_id, card_id)"); sys.exit(1)
for n in ("add_card_dependency", "edit_card_dependency"):
    a = args(n)
    if [x[0] for x in a] != ["board_id", "card_id", "target_card_id", "type", "color", "icon"]:
        print(f"t1: {n} args {[x[0] for x in a]}, want (board_id, card_id, target_card_id, type, color, icon) with the last three Optional defaults — C01 T1 pinned signature"); sys.exit(1)
    defaults = [ast.unparse(d) for d in funcs[n].args.defaults]
    if defaults[-3:] != ["None", "None", "None"]:
        print(f"t1: {n} must default type/color/icon to None (server defaults own the values), got {defaults}"); sys.exit(1)
a = args("remove_card_dependency")
if [x[0] for x in a] != ["board_id", "card_id", "target_card_id"]:
    print(f"t1: remove_card_dependency args {[x[0] for x in a]}, want (board_id, card_id, target_card_id)"); sys.exit(1)

# routes 1:1 to RESEARCH 1.3 (the pinned REST surface — nothing invented)
b = seg("list_board_dependencies")
if "/api/boards/{board_id}/dependencies" not in b or ".get(" not in b:
    print("t1: list_board_dependencies must GET /api/boards/{board_id}/dependencies (RESEARCH 1.3 board-wide route)"); sys.exit(1)
b = seg("list_card_dependencies")
if "/api/boards/{board_id}/cards/{card_id}/dependencies" not in b or ".get(" not in b:
    print("t1: list_card_dependencies must GET the one-card route (RESEARCH 1.3)"); sys.exit(1)
b = seg("add_card_dependency")
if "/api/boards/{board_id}/cards/{card_id}/dependencies" not in b or ".post(" not in b:
    print("t1: add_card_dependency must POST the card dependencies route"); sys.exit(1)
if '"cardId"' not in b:
    print("t1: add_card_dependency body must carry the pinned key \"cardId\""); sys.exit(1)
if "dependsOn" not in b:
    print("t1: add_card_dependency must document/accept the dependsOn body alias (RESEARCH 1.3)"); sys.exit(1)
# client-side 7-type validation BEFORE the request (create_label color-gate posture)
TYPES = ["related-to", "blocks", "is-blocked-by", "fixes", "is-fixed-by", "duplicates", "is-duplicated-by"]
missing = [t for t in TYPES if t not in src]
if missing:
    print(f"t1: the 7-type dependency list is incomplete in server.py — missing {missing} (C01 T1 client-side validation mirrors models/metadata/dependencies.js)"); sys.exit(1)
post_at = b.find(".post(")
rejected_before = (0 <= b.find("WekanError") < post_at) or re.search(r"_validate_[a-z_]*\(.*\)[^\n]*\n.*\.post\(", b)
if post_at == -1 or not rejected_before:
    print("t1: add_card_dependency must reject an unknown type (WekanError or a _validate_* helper) BEFORE the POST — the create_label color-gate posture (AC2)"); sys.exit(1)
d = ast.get_docstring(funcs["add_card_dependency"]) or ""
if "upsert" not in d.lower() or "duplicat" not in d.lower():
    print("t1: add_card_dependency docstring must document the UPSERT semantics (repeat-add UPDATES, never duplicates) — C01 T1"); sys.exit(1)
b = seg("edit_card_dependency")
if "/dependencies/{target_card_id}" not in b or ".put(" not in b:
    print("t1: edit_card_dependency must PUT /api/boards/{board_id}/cards/{card_id}/dependencies/{target_card_id}"); sys.exit(1)
b = seg("remove_card_dependency")
if "/dependencies/{target_card_id}" not in b or ".delete(" not in b:
    print("t1: remove_card_dependency must DELETE the target-scoped route"); sys.exit(1)
d = ast.get_docstring(funcs["remove_card_dependency"]) or ""
if "DESTRUCTIVE" not in d:
    print("t1: remove_card_dependency docstring must carry the DESTRUCTIVE marking (third destructive op — docstring-marked like remove_rule/delete_checklist_item)"); sys.exit(1)
print("ok: t1 — five dependency tools, pinned signatures, pinned routes, 7-type gate before POST, upsert doc, DESTRUCTIVE mark, writes only via _write_tool")
PY
  then fail "t1[C01 AC2]: the dependency-tools contract is not satisfied (reason above)"; fi
  ok "t1[C01 AC2]: five dependency tools registered per the RESEARCH 1.3 route map with client-side 7-type validation"
fi

# --- t2: preload_board — the one-call export reshape (C01 T2) --------------------
if want t2; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "preload_board" not in funcs:
    print("t2: preload_board is not defined in server.py yet — the cf-96 C01 T2 preload tool has not landed (designed red before C01 dev, not a harness fault)")
    sys.exit(1)
fn = funcs["preload_board"]
for d in fn.decorator_list:
    if isinstance(d, ast.Name) and d.id == "_write_tool":
        print("t2: preload_board is a READ (bare @mcp.tool) — registered via _write_tool it would vanish from the readonly tier"); sys.exit(1)
argn = [a.arg for a in fn.args.args]
if argn != ["board_id"]:
    print(f"t2: preload_board args {argn}, want (board_id)"); sys.exit(1)
b = ast.get_source_segment(src, fn)

if "/api/boards/{board_id}/export" not in b:
    print("t2: preload_board must GET /api/boards/{board_id}/export — ONE call (RESEARCH 2.2); no per-card fan-out"); sys.exit(1)
if "attachments" not in b or "false" not in b:
    print("t2: the export call must pass attachments=false — base64 payloads are a MUST-skip for preload (RESEARCH S11)"); sys.exit(1)
if "fields" not in b:
    print("t2: the export call must trim sections via ?fields= (unselected sections arrive as empty arrays — S11-exportFields)"); sys.exit(1)
for sec in ("board-header", "labels", "custom-fields", "dependencies", "sort"):
    if sec not in b:
        print(f"t2: the fields= vocabulary must include '{sec}' (C01 T2 trimmed section list)"); sys.exit(1)

# per-card key set EXACTLY the seven pinned fields: find the card-map dict
# literal by anchor keys and assert its full key set — an extra "title" or a
# dropped "sort" fails here (the AC2 "EXACTLY" wording is the contract).
KEYS = {"id", "card_number", "label_ids", "slug", "archived", "sort", "parent_id"}
card_dicts = []
for n in ast.walk(fn):
    if isinstance(n, ast.Dict):
        ks = {k.value for k in n.keys if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        if {"card_number", "parent_id"} <= ks:
            card_dicts.append(ks)
if not card_dicts:
    print("t2: no card-map dict literal carrying card_number + parent_id inside preload_board — the pinned per-card reshape (id/card_number/label_ids/slug/archived/sort/parent_id) has not landed"); sys.exit(1)
if not any(ks == KEYS for ks in card_dicts):
    print(f"t2: the preloaded card map keys are {sorted(card_dicts[0])}, want EXACTLY {sorted(KEYS)} (C01 T2 field set — titles/descriptions are NOT carried, per-card field set is pinned exactly)"); sys.exit(1)
if '"description"' in b:
    print("t2: preload_board must not carry descriptions — the payload drops them (C01 T2)"); sys.exit(1)

# archived: FLAGGED, never silently dropped — no conditional filtering on
# archived inside the tool (the flag is c.get(...); an If/comp-if on archived
# would drop cards in the tool instead of at the consumer).
def refs_archived(node):
    return "archived" in ast.unparse(node)
for n in ast.walk(fn):
    if isinstance(n, ast.If) and refs_archived(n.test):
        print("t2: preload_board filters on archived in an if — archived cards must be FLAGGED and stay in the payload; pickup-side filtering belongs to the consumer (C05)"); sys.exit(1)
    if isinstance(n, (ast.ListComp, ast.DictComp, ast.GeneratorExp)):
        for g in ast.walk(n):
            if isinstance(g, ast.comprehension) and any(refs_archived(iff) for iff in g.ifs):
                print("t2: preload_board drops archived cards in a comprehension filter — flag-not-drop contract violated (C01 AC2)"); sys.exit(1)

# the grouped map + the board's edge lines + name maps (pinned response keys)
for key in ("\"swimlanes\"", "\"lists\"", "\"cards\"", "\"dependencies\"", "\"label_names\"", "\"field_names\""):
    if key not in b:
        print(f"t2: the preload response must carry the pinned key {key} (swimlane→list→cards grouping + dependency lines + label/field name maps — C01 T2 contract)"); sys.exit(1)

d = ast.get_docstring(fn) or ""
if "customFields" not in b and "custom_fields" not in b:
    print("t2: slug must be extracted from the card's customFields entries (C01 T2 — the board's slug field id selects the value)"); sys.exit(1)
if "slug" not in d or ("[" not in d and "link" not in d.lower()):
    print("t2: preload_board docstring must document the combined [<slug>](<link>) value parsing (bracketed text; bare value passes through)"); sys.exit(1)
if "linked" not in d.lower():
    print("t2: preload_board docstring must state that linked cards are excluded by the exporter itself (S11 — documented, not filtered here)"); sys.exit(1)
print("ok: t2 — preload_board: one export call, attachments=false + fields trim, exact 7-key card map, no title/description, flag-not-drop archived, grouped map + dependencies + name maps")
PY
  then fail "t2[C01 AC2]: the preload_board reshape contract is not satisfied (reason above)"; fi
  ok "t2[C01 AC2]: preload_board one-call export reshape contract satisfied"
fi

# --- t3: set_card_labels — the bulk route wrapper (C01 T3, AD-74) -----------------
if want t3; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "set_card_labels" not in funcs:
    print("t3: set_card_labels is not defined in server.py yet — the cf-96 C01 T3 label tool (AD-74) has not landed (designed red before C01 dev)")
    sys.exit(1)
fn = funcs["set_card_labels"]
kind = None
for d in fn.decorator_list:
    if isinstance(d, ast.Name) and d.id == "_write_tool":
        kind = "write"
if kind != "write":
    print("t3: set_card_labels is a WRITE and must register through _write_tool (readonly tier hides it by construction)"); sys.exit(1)
argn = [a.arg for a in fn.args.args]
if argn[:2] != ["board_id", "card_ids"]:
    print(f"t3: set_card_labels must start (board_id, card_ids, ...) — board_id required per house style, got {argn}"); sys.exit(1)
if argn != ["board_id", "card_ids", "add_label_ids", "remove_label_ids"]:
    print(f"t3: set_card_labels args {argn}, want (board_id, card_ids, add_label_ids=None, remove_label_ids=None)"); sys.exit(1)
b = ast.get_source_segment(src, fn)
if "/api/boards/{board_id}/cards/labels" not in b or ".post(" not in b:
    print("t3: set_card_labels must POST the upstream bulk route /api/boards/{board_id}/cards/labels (RESEARCH 2.1/S9)"); sys.exit(1)
for key in ('"cardIds"', '"addLabelIds"', '"removeLabelIds"'):
    if key not in b:
        print(f"t3: the bulk body must carry the pinned key {key}"); sys.exit(1)
if "500" not in src or b.find(".post(") == -1:
    print("t3: set_card_labels must enforce the ≤500 card cap client-side (the route's own bound — document AND gate it) — the '500' constant is not reachable in server.py or the bulk POST is missing"); sys.exit(1)
post_at = b.find(".post(")
cap_before_send = (0 <= b.find("WekanError") < post_at) or "_validate_" in b[:post_at] or "500" in b[:post_at]
if not cap_before_send:
    print("t3: the >500 rejection must happen BEFORE the bulk POST (validate-before-send posture, C01 T3)"); sys.exit(1)
if "labels" not in b or ".get(" not in b:
    print("t3: set_card_labels must validate the label ids against the board before the bulk POST (read the board's labels — the route's own board-membership gate stays the authority)"); sys.exit(1)
d = ast.get_docstring(fn) or ""
if "no-op" not in d.lower() and "no op" not in d.lower():
    print("t3: set_card_labels docstring must state that an absent list is a no-op (add-only / remove-only calls are legal — C01 T3)"); sys.exit(1)
print("ok: t3 — set_card_labels: bulk route + pinned body keys, board_id-led args, ≤500 gate before POST, board-label validation, no-op docstring")
PY
  then fail "t3[C01 AC2]: the set_card_labels contract is not satisfied (reason above)"; fi
  ok "t3[C01 AC2]: set_card_labels bulk-shape contract satisfied"
fi

# --- t4: _slim_card passthroughs + by-list strip-accuracy (C01 T4) ----------------
if want t4; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def seg(name):
    return ast.get_source_segment(src, funcs[name])
if "_slim_card" not in funcs:
    print("t4: _slim_card disappeared from server.py"); sys.exit(1)
s = seg("_slim_card")
if '"card_dependencies"' not in s or "cardDependencies" not in s:
    print("t4: _slim_card must pass card_dependencies through from the wire key cardDependencies — today silently dropped (RESEARCH 2.1, C01 T4 — not landed yet if this is red)")
    sys.exit(1)
if '"parent_id"' not in s or "parentId" not in s:
    print("t4: _slim_card must pass parent_id through from the wire key parentId (C01 T4)"); sys.exit(1)
lic = seg("list_cards_in_list")
if "/api/cards/" in lic:
    print("t4: list_cards_in_list must NOT gain per-card /api/cards/ fetches to compensate — it stays the strip-accurate by-list read (C01 T4)"); sys.exit(1)
d = ast.get_docstring(funcs["list_cards_in_list"]) or ""
if "projection" not in d.lower():
    print("t4: list_cards_in_list docstring must keep documenting the by-list projection strip"); sys.exit(1)
print("ok: t4 — _slim_card carries card_dependencies + parent_id; list_cards_in_list stays strip-accurate (no N+1 fetch)")
PY
  then fail "t4[C01 AC2]: the passthrough contract is not satisfied (reason above)"; fi
  ok "t4[C01 AC2]: _slim_card passthroughs + by-list strip-accuracy hold"
fi

# --- t5: create_card parent_id — two-step, OQ1 parentId-only (C01 T5) -------------
if want t5; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
if "create_card" not in funcs:
    print("t5: create_card disappeared"); sys.exit(1)
cc = funcs["create_card"]
argn = [a.arg for a in cc.args.args]
if argn[-1] != "parent_id":
    print(f"t5: create_card must end with the optional trailing parent_id parameter (after default_checked), got {argn} — the C01 T5 two-step has not landed"); sys.exit(1)
ann = ast.unparse(cc.args.args[-1].annotation) if cc.args.args[-1].annotation else None
if ann != "Optional[str]":
    print(f"t5: parent_id must be Optional[str], got {ann}"); sys.exit(1)
if ast.unparse(cc.args.defaults[-1]) != "None":
    print("t5: parent_id must default to None (absent = the create behaves exactly as today)"); sys.exit(1)
b = ast.get_source_segment(src, cc)
if '_validate_default_checked(' not in b:
    print("t5: the existing default_checked validation leg must survive the parent_id extension (regression)"); sys.exit(1)
if '"parentId"' not in b or '.put(' not in b:
    print("t5: parent_id must ride the two-step create→PUT /api/boards/{board_id}/cards/{card_id} body parentId (RESEARCH S9 — the single-card POST does not honor a body parentId)"); sys.exit(1)
if "/api/boards/{board_id}/cards/{card_id}" not in b:
    print("t5: the PUT target must be the single-card route /api/boards/{board_id}/cards/{card_id} (S9)"); sys.exit(1)
if "parent_id_set" not in b:
    print("t5: a failed PUT must surface parent_id_set: false + reason in the response (the default_checked outcome-surfacing posture)"); sys.exit(1)
if ".delete(" in b:
    print("t5: create_card must never roll the card back on a parent_id failure — a delete call inside it breaks the non-rollback contract (C01 T5)"); sys.exit(1)
# OQ1 negative pin: parentId-only — no Red Strings edge drawn automatically
if "/api/boards/{board_id}/dependencies" in b or "card_dependency(" in b or "_wekan.post(f\"/api/boards/{board_id}/cards/{card_id}/dependencies" in b:
    print("t5: create_card REFERENCES the dependency routes — the OQ1 ruling makes parent_id the ONLY follow-up representation (no automatic edge creation; the AC2 negative pin)"); sys.exit(1)
d = ast.get_docstring(cc) or ""
if "parentId" not in b and "parent" not in d.lower():
    print("t5: create_card docstring must document the parent_id lineage semantics (two-step rationale + failure surfacing)"); sys.exit(1)
print("ok: t5 — create_card parent_id: trailing Optional[str], create→PUT parentId, parent_id_set surfaced, no rollback, no auto dependency edge (OQ1)")
PY
  then fail "t5[C01 AC2]: the create_card parent_id contract is not satisfied (reason above)"; fi
  ok "t5[C01 AC2]: create_card parent_id two-step + OQ1 negative pin hold"
fi

# --- t6: doc re-stamp parity (C01 T6 + AC4) ----------------------------------------
if want t6; then
  if ! python3 - "$README" "$SKILL_MCP" "$SHAPES" "$SKILL_API" <<'PY'
import re, sys

readme, skill, shapes, api = (open(p).read() for p in sys.argv[1:5])
def bad(m):
    print(f"t6: {m} — the C01 docs re-stamp (README/skill/call-shapes) must land in the SAME commit as the tools (DECISIONS doc-parity convention)")
    sys.exit(1)

NEW = ["list_board_dependencies", "list_card_dependencies", "add_card_dependency",
       "edit_card_dependency", "remove_card_dependency", "preload_board", "set_card_labels"]

if "38 typed tools" not in readme:
    bad("README still carries the pre-cf-96 tool count (must state the 38-tool surface)")
for stale in ("31 typed tools", "30 typed tools"):
    if stale in readme:
        bad(f"README still claims a stale tool count ({stale!r})")
for n in NEW:
    if n not in readme:
        bad(f"README tool section is missing {n}")

# tier table counts (both full tiers) + the write-surface list + the
# intentionally-omitted note staying true with dependencies NOT omitted
if skill.count("full, 38 tools") < 2:
    bad("the wekan-mcp SKILL tier table must state 'full, 38 tools' on both full tiers (dev-boards + gpu admin)")
if "full, 31 tools" in skill:
    bad("the SKILL tier table still says 'full, 31 tools'")
for n in NEW:
    if n not in skill:
        bad(f"SKILL surface list is missing {n}")
i = skill.lower().find("intentionally omitted")
if i < 0:
    bad("SKILL lost its intentionally-omitted note (C01 T6: the note must STAY — dependencies are NOT among the omissions)")
window = skill[i:i + 500].lower()
if "dependen" in window:
    bad("the intentionally-omitted window now names dependencies — wrong direction: the dependency tools SHIP, the omission list must stay dependency-free")

if "all 38 tools" not in shapes and "38 tools" not in shapes:
    bad("call-shapes.md still counts 31 tools in its header")
for n in NEW:
    rows = [l for l in shapes.splitlines() if re.match(rf"^\| `{n}` \|", l)]
    if len(rows) != 1:
        bad(f"call-shapes.md needs exactly one row for {n} (8-row table extension — C01 T6)")
        continue
    if "source-only 2026-11" not in rows[0]:
        bad(f"call-shapes.md row {n} must carry the evidence stamp 'source-only 2026-11' — nothing pre-C10 may claim live (AC4)")
    if "live probe" in rows[0]:
        bad(f"call-shapes.md row {n} claims a live probe — the routes were never agent-probed (no bearer); the C10 runbook upgrades the stamp AFTER the user probe")

if "38 typed tools" not in api:
    bad("wekan-api SKILL still enumerates the stale tool count (C01 T6: count mentions update)")
print("ok: t6 — README 38 + names, tier table 38x2, omitted-note intact, call-shapes rows stamped source-only 2026-11, wekan-api count current")
PY
  then fail "t6[C01 AC4]: the documentation-parity re-stamp is not satisfied (reason above)"; fi
  ok "t6[C01 T6/AC4]: docs re-stamped to 38 tools with honest source-only evidence stamps"
fi

# --- t7: wekan.py byte-unchanged (C01 AC3, tools.sh t8 posture) --------------------
if want t7; then
  git rev-parse --verify "$PIN_BASE" >/dev/null 2>&1 \
    || fail "harness: base ref '$PIN_BASE' does not resolve (CF96_BASE=<ref>)"
  git diff --quiet "$PIN_BASE" -- "$WEKAN_PY" \
    || fail "t7[C01 AC3]: $WEKAN_PY changed since $PIN_BASE — C01 rides the existing _wekan helpers and must not edit the login-mint client (pass CF96_BASE=<ref> if main legitimately moved it)"
  ok "t7[C01 AC3]: $WEKAN_PY byte-identical to $PIN_BASE (tools.sh t8 companion pin)"
fi

# --- t8: _slim_rule capture projection — the schema-2 keys (C11 T1 / AC1) ----------
if want t8; then
  if ! python3 - "$SERVER" <<'PY'
import ast, sys

src = open(sys.argv[1]).read()
tree = ast.parse(src)
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
fn = funcs.get("_slim_rule")
if fn is None:
    print("t8: _slim_rule disappeared from server.py (layout fault, not a C11 red)"); sys.exit(1)
ret = next((n for n in ast.walk(fn) if isinstance(n, ast.Return)), None)
if ret is None or not isinstance(ret.value, ast.Dict):
    print("t8: _slim_rule must return a dict literal — the projection is pinned structurally (C11 T1)"); sys.exit(1)
d = ret.value
keys = [k.value for k in d.keys if isinstance(k, ast.Constant)]
WANT = {"id", "title", "trigger", "action", "extra_actions", "extra_triggers", "enabled"}
if set(keys) != WANT:
    print(f"t8: _slim_rule projects {sorted(keys)}, want EXACTLY {sorted(WANT)} (C11 T1 — the schema-2 capture contract keys)"); sys.exit(1)
WIRE = {"id": "_id", "title": "title", "trigger": "trigger", "action": "action",
        "extra_actions": "extraActions", "extra_triggers": "extraTriggers", "enabled": "enabled"}
for k, v in zip(d.keys, d.values):
    raw = (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
           and v.func.attr == "get" and isinstance(v.func.value, ast.Name)
           and v.func.value.id == "r"
           and v.args and isinstance(v.args[0], ast.Constant)
           and v.args[0].value == WIRE[k.value])
    if not raw:
        print(f"t8: key {k.value!r} must read r.get(\"{WIRE[k.value]}\") — the route value un-reshaped (C11 T1), got {ast.unparse(v)}"); sys.exit(1)
en = d.values[keys.index("enabled")]
if not (len(en.args) == 2 and isinstance(en.args[1], ast.Constant) and en.args[1].value is True):
    print("t8: enabled must be r.get(\"enabled\", True) — True ONLY when the route omits the field; a paused rule must read enabled: false (C11 T1, RESEARCH F6c)"); sys.exit(1)
for key in ("extra_actions", "extra_triggers"):
    v = d.values[keys.index(key)]
    if len(v.args) != 1:
        print(f"t8: {key} must pass through r.get(\"{WIRE[key]}\") with NO default — an omitted field reads None, never an invented empty list (the _slim_card parent_id posture; absence stays visibly absent)"); sys.exit(1)

def plain_read(name):
    f = funcs.get(name)
    if f is None:
        return False
    has = any(isinstance(x, ast.Attribute) and x.attr == "tool"
              and isinstance(x.value, ast.Name) and x.value.id == "mcp"
              for x in f.decorator_list)
    gated = any(isinstance(x, ast.Name) and x.id == "_write_tool" for x in f.decorator_list)
    return has and not gated
for name in ("get_rule", "list_rules"):
    if not plain_read(name):
        print(f"t8: {name} must stay a plain @mcp.tool READ — the READ-ONLY tier keeps exposing the rule projection (C11 T1 registration-unchanged duty)"); sys.exit(1)

d1 = ast.get_docstring(funcs["get_rule"]) or ""
if "checklist extras" not in d1 or "enabled" not in d1:
    print("t8: get_rule docstring must re-stamp to the full embedded trigger, action, checklist extras and enabled flag (C11 T1)"); sys.exit(1)
d2 = ast.get_docstring(funcs["list_rules"]) or ""
if "extra_actions" not in d2 or "enabled" not in d2:
    print("t8: list_rules docstring must carry the 7-key shape claim (C11 T1/T2 doc parity)"); sys.exit(1)
print("ok: t8 — _slim_rule EXACTLY the 7-key capture projection, raw r.get pass-throughs (no reshaping), enabled True-only-on-omission, get_rule/list_rules plain reads, docstrings re-stamped")
PY
  then fail "t8[C11 AC1]: the _slim_rule capture-projection contract is not satisfied (reason above)"; fi
  ok "t8[C11 AC1]: _slim_rule carries extra_actions/extra_triggers/enabled un-reshaped — the schema-2 capture path is executable"
fi

printf 'PASS: wekan-mcp cf-96 dependency/preload/label-surface checks (%d ok)\n' "$checks"
